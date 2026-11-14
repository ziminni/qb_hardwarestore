# pyright: reportAttributeAccessIssue=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/models.py and apps/pos/services.py: the checker
# resolves its config from its WORKING DIRECTORY, so no pyrightconfig.json is found, and
# `Model.objects` is a false positive on valid Django without django-stubs.
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from apps.inventory.services import lock_selling_unit_lines, pick_up_caption
from common.exceptions import refuse_fractional_whole_unit, refuse_inactive_selling_unit

from .models import (
    Customer,
    Delivery,
    HeldCart,
    HeldCartItem,
    OfficialReceipt,
    Payment,
    Quotation,
    QuotationItem,
    SalesItem,
    SalesOrder,
    SalesOrderItem,
    SalesTransaction,
    Shift,
)


class CustomerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Customer
        fields = [
            "id",
            "name",
            "customer_type",
            "contact_details",
            "tin_no",
            "total_credit_limit",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class PaymentSerializer(serializers.ModelSerializer):
    decided_by_name = serializers.CharField(
        source="decided_by.full_name", read_only=True, default=None
    )

    class Meta:
        model = Payment
        fields = [
            "id",
            "transaction",
            "method",
            "amount_tendered",
            "reference_no",
            # Phase 4 task B2 (decision 18): the cheque facts and where the decision
            # stands. `status` is CLEARED for every tender that is money in hand, and
            # PENDING/BOUNCED/CLEARED for a cheque.
            "status",
            "cheque_number",
            "bank",
            "cheque_date",
            "ledger",
            "decided_by",
            "decided_by_name",
            "decided_at",
            "decision_reason",
            "timestamp",
        ]
        # The cheque lifecycle is the SERVER's: only `clear/` and `bounce/` move it, so a
        # client echoing a sale body back cannot mark its own cheque cleared.
        read_only_fields = [
            "id",
            "timestamp",
            "status",
            "decided_by",
            "decided_at",
            "decision_reason",
        ]


class ChequeSerializer(serializers.ModelSerializer):
    """One row of the cheque queue (`GET /api/v1/cheques/`, decision 18).

    A cheque IS a `Payment` with `method=CHEQUE`, so this is that row read from the side
    the clearance screen needs: whose cheque it is, which sale and which utang it answers
    for, what it is worth, and who decided it and when. `amount` is named for what the
    screen shows (2-decimal string, like every other money field on the wire).
    """

    customer = serializers.IntegerField(
        source="transaction.customer_id", read_only=True
    )
    customer_name = serializers.CharField(
        source="transaction.customer.name", read_only=True
    )
    transaction_no = serializers.CharField(
        source="transaction.transaction_no", read_only=True
    )
    amount = serializers.DecimalField(
        source="amount_tendered", max_digits=12, decimal_places=2, read_only=True
    )
    received_at = serializers.DateTimeField(source="timestamp", read_only=True)
    decided_by_name = serializers.CharField(
        source="decided_by.full_name", read_only=True, default=None
    )

    class Meta:
        model = Payment
        fields = [
            "id",
            "transaction",
            "transaction_no",
            "customer",
            "customer_name",
            "ledger",
            "amount",
            "cheque_number",
            "bank",
            "cheque_date",
            "status",
            "reference_no",
            "received_at",
            "decided_by",
            "decided_by_name",
            "decided_at",
            "decision_reason",
        ]
        read_only_fields = fields


class SalesItemSerializer(serializers.ModelSerializer):
    """One sale line, with where it was PICKED UP (Phase 5 B4, decision 18; Phase 9 B2).

    `stored_at` / `stored_at_name` are the product's label, read-only: a sale line does
    not choose a shelf, it reports the one the product has. They STAY for old clients.

    Phase 9 B2 (decision 21 §2) adds `pick_up`: the shelves this line actually left, in
    the order the allocator took them ("3 at Store, 2 at Bodega"). It is read from the
    line's `SalesItemDeduction` rows, so the caption reports a FACT rather than the
    product's label; a line with no rows (a pre-Phase-9 sale, an unfulfilled order) falls
    back to one entry naming `stored_at`, which is the caption the receipt printed before.

    `stored_at_name` prefers an annotation the VIEW attached (`getattr(obj, ...)`, the
    same pattern as `VariantUOMSerializer.get_in_use`) and otherwise walks the relation.
    The walk costs a query per line when a list serializer has not joined
    `variant_uom__variant__product__stored_at`; that join lives in `apps/pos/views.py`.
    """

    variant_uom_code = serializers.CharField(
        source="variant_uom.uom.code", read_only=True
    )
    stored_at = serializers.IntegerField(
        source="variant_uom.variant.product.stored_at_id", read_only=True
    )
    stored_at_name = serializers.SerializerMethodField()
    pick_up = serializers.SerializerMethodField()

    class Meta:
        model = SalesItem
        fields = [
            "id",
            "transaction",
            "variant_uom",
            "variant_uom_code",
            "qty",
            "unit_price",
            "subtotal",
            "stored_at",
            "stored_at_name",
            "pick_up",
        ]
        read_only_fields = ["id", "subtotal"]

    def get_stored_at_name(self, obj):
        annotated = getattr(obj, "stored_at_name", None)
        if annotated is not None:
            return annotated
        return obj.variant_uom.variant.product.stored_at.name

    def get_pick_up(self, obj):
        from apps.inventory.services import pick_up_caption

        uom = obj.variant_uom
        # `deductions` is prefetched by the transaction viewsets, so a page of sales costs
        # ONE query for the whole page rather than one per line.
        return pick_up_caption(
            parts=[
                (row.batch.location_id, row.batch.location.name, row.qty)
                for row in obj.deductions.all()
            ],
            fallback_location_id=uom.variant.product.stored_at_id,
            fallback_location_name=self.get_stored_at_name(obj),
            qty=obj.qty,
            conversion_factor=uom.conversion_factor,
            selling_unit=uom.uom.code,
            base_unit=uom.variant.base_uom.code,
        )


class OfficialReceiptSerializer(serializers.ModelSerializer):
    class Meta:
        model = OfficialReceipt
        fields = ["id", "transaction", "or_number", "terminal_no", "printed_at"]
        read_only_fields = ["id", "printed_at"]


class SalesTransactionSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    cashier_name = serializers.CharField(source="cashier.full_name", read_only=True)
    items = SalesItemSerializer(many=True, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    receipt = OfficialReceiptSerializer(read_only=True)

    class Meta:
        model = SalesTransaction
        fields = [
            "id",
            "customer",
            "customer_name",
            "cashier",
            "cashier_name",
            "transaction_no",
            "trans_date",
            "vat_registered",
            "vat_rate",
            "vatable_sales",
            "vat_amount",
            "discount_amount",
            "discount_reason",
            # Phase 5 task B3 (decision 18): the delivery charge is inside grand_total
            # and outside discount_amount. Read-only - it comes from the `delivery`
            # object on the checkout body, never from a money field the client can set.
            "delivery_fee",
            "grand_total",
            "change_given",
            "source",
            "original_transaction",
            "status",
            "notes",
            "items",
            "payments",
            "receipt",
            "created_at",
            "updated_at",
        ]
        # `cashier` is READ-ONLY because the actor is not the client's to choose. The view
        # already passes `cashier=request.user` into `process_sale`, so a writable
        # `cashier` was demanded by validation and then discarded -- every client had to
        # send a value that had no effect, and a client could have attributed a sale to
        # another cashier. Same invariant as StockAdjustmentSerializer.user (Phase 2),
        # found here by POSTing a valid sale to the endpoint: HTTP 400
        # {"cashier": ["This field is required."]}.
        # `vat_registered`, `vat_rate`, the three money fields and `discount_reason` are
        # DERIVED from
        # the settings, the cart and (above the cap) the approval, all inside
        # `process_sale` - `views.SalesTransactionViewSet.create` never reads them from
        # the payload. Read-only so an older client that echoes a sale body back cannot
        # write them, and so the receipt's VAT cannot be dictated by the till (decision
        # 18: the server is the trust boundary).
        read_only_fields = [
            "id",
            "transaction_no",
            "trans_date",
            "created_at",
            "updated_at",
            "cashier",
            "vat_registered",
            "vat_rate",
            "vatable_sales",
            "vat_amount",
            "discount_amount",
            "discount_reason",
            # QA High (Phase 4 close): change handed back is money OUT of the drawer and
            # is derived by `process_sale` from the tenders the server stored, so a till
            # that echoes it back cannot write it (the same trust boundary as VAT above).
            "change_given",
        ]


class ShiftSerializer(serializers.ModelSerializer):
    """Phase 4 (decision 06).

    `cashier` is read-only because the actor is never the client's to choose - the view
    takes `request.user`, the same invariant as SalesTransactionSerializer.cashier.
    `status` and `closed_at` are read-only because only the open/close ACTIONS may move
    them: a writable status would let a client reopen a closed shift, which decision 06
    forbids (OPEN -> CLOSED, never back).

    `z_reading` is derived on read from the shift's own transactions, so a closed shift
    prints identical numbers every time and no second table can drift from the sales.

    `held_cart_count` (Phase 3 Task 3) is derived and READ-ONLY for the same reason: a
    client that could write it would be able to silence the close advisory. It is the
    number of parked carts belonging to this shift's cashier - advisory only, because
    decision 06 makes the close record-and-warn rather than block.
    """

    cashier_name = serializers.CharField(source="cashier.full_name", read_only=True)
    z_reading = serializers.SerializerMethodField()
    held_cart_count = serializers.SerializerMethodField()

    class Meta:
        model = Shift
        fields = [
            "id",
            "cashier",
            "cashier_name",
            "status",
            "opening_float",
            "closing_count",
            "opened_at",
            "closed_at",
            "notes",
            "z_reading",
            "held_cart_count",
        ]
        read_only_fields = [
            "id",
            "cashier",
            "status",
            "opened_at",
            "closed_at",
            "held_cart_count",
        ]

    def get_z_reading(self, obj):
        # Imported here, not at module level: services imports these models, and a
        # module-level import in both directions is a cycle waiting for the next edit.
        from .services import compute_z_reading

        return compute_z_reading(obj)

    def get_held_cart_count(self, obj):
        from .services import held_cart_count

        return held_cart_count(obj)


class QuotationItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuotationItem
        fields = ["id", "quotation", "variant_uom", "qty", "unit_price"]
        # `quotation` is READ-ONLY: the parent QuotationSerializer.create() sets it. Leaving it
        # writable made it a required field on every nested item, so a legitimate payload was
        # rejected with "quotation: This field is required." - which is what the first GREEN run hit.
        read_only_fields = ["id", "quotation"]

    def validate(self, attrs):
        # A quote must refer to a currently sellable catalogue row.
        vuom = attrs.get("variant_uom")
        if vuom is not None:
            refuse_inactive_selling_unit(variant_uom=vuom, what=str(vuom.variant))
        qty = attrs.get("qty")
        if vuom is not None and qty is not None:
            refuse_fractional_whole_unit(
                is_whole=vuom.uom.is_whole,
                qty=qty,
                what=f"{vuom.variant}, {vuom.uom.code}",
            )
        return attrs


class QuotationSerializer(serializers.ModelSerializer):
    items = QuotationItemSerializer(many=True, required=False)

    class Meta:
        model = Quotation
        fields = [
            "id",
            "quotation_no",
            "customer",
            "status",
            "valid_until",
            "notes",
            "items",
            "created_at",
            "updated_at",
        ]
        # quotation_no and created_by are the server's to decide; a client that could set
        # either could forge a number or attribute a quotation to someone else. `status`
        # joins them (Phase 6 B1, decision 22 #16): a quotation's life cycle is not a
        # client's to write, which is why the SalesQuoteStatus vocabulary is server-side.
        read_only_fields = ["id", "quotation_no", "status", "created_at", "updated_at"]

    def validate(self, attrs):
        # Phase 6 B1 (decision 22 #16): the lines are written ONCE, with the document.
        # DRF's model serializer cannot nest a writable `items` into an update - it
        # raises an AssertionError, which is a 500 on an ordinary PATCH. Refusing the
        # request here is the 400 it always was.
        if self.instance is not None and "items" in attrs:
            raise serializers.ValidationError(
                {
                    "items": "Quotation lines cannot be rewritten in place. Void this "
                    "quotation and issue a new one."
                }
            )
        return attrs

    def create(self, validated_data):
        items = validated_data.pop("items", [])
        # Phase 1d Task 3 (decision 16): the items were validated BEFORE this write, so
        # the catalogue can lose a unit in between. The whole document - parent and
        # lines - is one transaction holding the unit locks, so a refusal leaves no
        # orphan quotation and the removal cannot walk through the gap either.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            lock_selling_unit_lines(
                ((item["variant_uom"], item) for item in items), document="quotation"
            )
            quotation = Quotation.objects.create(**validated_data)
            for item in items:
                QuotationItem.objects.create(quotation=quotation, **item)
        return quotation


class SalesOrderItemSerializer(serializers.ModelSerializer):
    # Phase 7 B1 (decision 19 #3): what has been fulfilled, what was cancelled, and what
    # is left. `remaining_qty` is the MODEL's arithmetic, not a second copy of it.
    remaining_qty = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = SalesOrderItem
        # Tuples, not lists: same reason as the Delivery serializer below - this file's
        # other serializers carry one RUF012 each for these attributes.
        fields = (
            "id",
            "order",
            "variant_uom",
            "qty",
            "unit_price",
            "fulfilled_qty",
            "cancelled_qty",
            "remaining_qty",
        )
        # `order` is read-only for the same reason `quotation` is on the item serializer above:
        # the parent's create() sets it, and leaving it writable makes it REQUIRED on every nested
        # item, rejecting a legitimate payload.
        # The three quantity columns are SERVER-owned (decision 19): a client that could set
        # `fulfilled_qty` could claim a promise was kept without ringing a sale.
        read_only_fields = (
            "id",
            "order",
            "fulfilled_qty",
            "cancelled_qty",
            "remaining_qty",
        )

    def validate(self, attrs):
        # An order must refer to a currently sellable catalogue row.
        vuom = attrs.get("variant_uom")
        if vuom is not None:
            refuse_inactive_selling_unit(variant_uom=vuom, what=str(vuom.variant))
        qty = attrs.get("qty")
        if vuom is not None and qty is not None:
            refuse_fractional_whole_unit(
                is_whole=vuom.uom.is_whole,
                qty=qty,
                what=f"{vuom.variant}, {vuom.uom.code}",
            )
        return attrs


class SalesOrderSerializer(serializers.ModelSerializer):
    items = SalesOrderItemSerializer(many=True, required=False)
    # Phase 7 B1 (decision 19): the wire carries the status the RULES see, so a legacy
    # PROCESSING/READY row shows as CONFIRMED here exactly as it does to B3/B4. Declared
    # (not a model field) because it reads `effective_status`; declaring it also makes it
    # definitively read-only, so no client can name a status - the actions in B3/B4 do.
    status = serializers.CharField(source="effective_status", read_only=True)
    # Phase 5 task B3 (decision 18): an order may be marked Deliver. WRITE-ONLY and a
    # plain object, NOT a nested ModelSerializer: the delivery's rules (address, contact,
    # date, a fee in whole centavos) live in ONE place - `services._validated_delivery` -
    # so the order form and the till cannot disagree about what a delivery is.
    delivery = serializers.DictField(write_only=True, required=False)
    # Phase 7 B2 (decision 19 #1): a manager's one-time approval token for an order whose
    # largest line discount is above the Admin's cap. Write-only - a token is a credential
    # for one save, not part of what an order IS - and spent in `create` below.
    discount_approval = serializers.CharField(
        write_only=True, required=False, allow_blank=True
    )
    # Phase 7 B3 (decision 19 #4): the manager's EDIT reuses `items` for the whole line
    # set - one key for lines on create and on edit, because it is the same list - and a
    # nested per-line patch (an entry carrying `id`) is refused in `validate` below: a
    # document somebody promised is replaced whole, never patched a row at a time.
    # The reason an edit is being made. Required on PATCH (checked in `validate` below),
    # audited, and never stored: an order's lines and notes are the correction, and the
    # audit trail is where the explanation belongs.
    reason = serializers.CharField(
        write_only=True,
        required=False,
        max_length=255,
        # Blank is allowed at FIELD level so `validate` below can answer it with the
        # stable `SALES_ORDER_REASON_REQUIRED` code the client branches on, instead of
        # DRF's field sentence.
        allow_blank=True,
    )

    class Meta:
        model = SalesOrder
        fields = [
            "id",
            "order_no",
            "customer",
            "quotation",
            "status",
            "notes",
            "items",
            # Phase 5 task B3 (decision 18): write-only, accepted on create only.
            "delivery",
            # Phase 7 B2 (decision 19 #1): write-only, the manager's approval token.
            "discount_approval",
            # Phase 7 B3 (decision 19 #4): the edit's required, audited reason. Write-only,
            # so the wire shape of an order is byte-identical to B1/B2.
            "reason",
            "created_at",
            "updated_at",
        ]
        # `status` is the declared read-only field above (Phase 7 B1, decision 19): a
        # POST body does not get to choose the starting status, and the wire shows the
        # EFFECTIVE one so legacy READY rows read as CONFIRMED.
        read_only_fields = ("id", "order_no", "created_at", "updated_at")

    def to_representation(self, instance):
        """Add each line's live stock hint (Phase 7 B5, decision 19 #2).

        Injected here rather than as a serializer-method field on the LINE serializer
        because the hint costs one stock query for the WHOLE order: a per-line field
        would spend one query per line, and the order list renders many orders. Keyed by
        the rendered line `id`, so no assumption is made about row order.
        """
        data = super().to_representation(instance)
        from .services import order_line_available_qty

        hints = order_line_available_qty(instance.items.all())
        for row in data["items"]:
            hint = hints.get(row["id"])
            row["available_qty"] = "0.00" if hint is None else f"{hint:.2f}"
        return data

    def create(self, validated_data):
        items = validated_data.pop("items", [])
        delivery_data = validated_data.pop("delivery", None)
        discount_approval = validated_data.pop("discount_approval", None)
        # Phase 7 B3 review: `reason` belongs to the EDIT and the CANCEL, where it is
        # audited; an order has no column for it (`cancel_reason` is the cancellation's).
        # Popped here because a client that echoes the field on create would otherwise
        # reach `SalesOrder.objects.create(reason=...)` and die as a TypeError 500.
        validated_data.pop("reason", None)
        # Same rule, lock and single transaction as a quotation above.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            lock_selling_unit_lines(
                ((item["variant_uom"], item) for item in items), document="sales order"
            )
            # Phase 7 B2 (decision 19 #1): the per-line price guard runs HERE - inside the
            # saving transaction and before the first write - so a refused discount leaves
            # no order, no lines and no audit row, and the approval it consumes rolls back
            # with the order if a later write fails.
            from .services import guard_order_line_prices

            approval = guard_order_line_prices(
                lines=((item["variant_uom"], item["unit_price"]) for item in items),
                discount_approval=discount_approval,
            )
            order = SalesOrder.objects.create(**validated_data)
            for item in items:
                SalesOrderItem.objects.create(order=order, **item)
            # The token is spent by THIS order, in the same transaction: the approval row
            # records that the price on this order was signed off, so B4's fulfilment
            # charges the agreed price without asking the manager again.
            if approval is not None:
                approval.used_at = timezone.now()
                approval.sales_order = order
                approval.save(update_fields=["used_at", "sales_order"])
            # Phase 5 task B3: the delivery row commits or rolls back WITH the order.
            # The fee stays on this row (an order carries no money total on the wire) and
            # the FIRST fulfilment (Phase 7 B4) moves the slip onto that sale, carrying
            # the fee into its `grand_total` exactly once.
            if delivery_data is not None:
                from .services import create_delivery

                order.delivery = create_delivery(
                    data=delivery_data, created_by=order.created_by, sales_order=order
                )
        return order

    # Phase 7 B3 (decision 19 #4): what an EDIT may carry. Anything else in the body -
    # a new customer, a different quotation - is refused rather than silently ignored,
    # because an order that reads back differently from what the manager sent is worse
    # than a 400.
    EDITABLE_FIELDS = ("notes",)

    def validate(self, attrs):
        if self.instance is None:
            # B5 (decision 19's premise, now code): a fulfilment rings the ORDER's
            # customer into an ordinary sale, and only a named customer may owe
            # (decision 14). An order on the walk-in placeholder would promise goods to
            # nobody, so it is refused HERE - before the order, its lines and its audit
            # row exist.
            from .exceptions import WalkInCannotOrder

            customer = attrs.get("customer")
            if customer is not None and customer.customer_type == Customer.Type.WALK_IN:
                raise WalkInCannotOrder(customer.name)
            return attrs
        from .exceptions import SalesOrderReasonRequired

        # A per-line patch (`{"items": [{"id": 3, "qty": "2.00"}]}`) is NOT an edit this
        # API offers: lines are replaced as a whole. Checked on the RAW body because
        # `id` is read-only on the nested serializer and never reaches `attrs`.
        raw_items = (self.initial_data or {}).get("items")
        if isinstance(raw_items, list) and any(
            isinstance(entry, dict) and "id" in entry for entry in raw_items
        ):
            raise serializers.ValidationError(
                {
                    "items": "Lines are replaced as a whole, not patched one at a "
                    "time: send every line without its `id`."
                }
            )
        # Decision 19 #4: an edit is a reasoned act, and the sentence is the audit trail.
        if not (attrs.get("reason") or "").strip():
            raise SalesOrderReasonRequired(what="edited")
        refused = sorted(
            set(attrs)
            - set(self.EDITABLE_FIELDS)
            - {"items", "delivery", "discount_approval", "reason"}
        )
        if refused:
            raise serializers.ValidationError(
                {
                    field: "An order edit changes its lines, its notes or its delivery."
                    for field in refused
                }
            )
        return attrs

    def update(self, instance, validated_data):
        """Edit a promise the shop has not started keeping (B3, decision 19 #4).

        The caller (`SalesOrderViewSet.partial_update`) holds the order's row lock and
        wraps this in the edit's transaction, so the state read here cannot be raced by a
        fulfilment: the loser of that race either sees PARTIAL and is refused, or lands
        first and this edit is refused.

        Order of work is the order `create` uses, and for the same reason: the price
        guard runs BEFORE the first write, so a discount refused for want of a token
        leaves the old lines, the old notes and no audit row behind.
        """
        from .exceptions import SalesOrderEditRefused
        from .services import guard_order_line_prices

        order = instance
        items = validated_data.pop("items", None)
        delivery_data = validated_data.pop("delivery", None)
        discount_approval = validated_data.pop("discount_approval", None)
        # The reason is audited by the view, which reads it before calling `save`; there
        # is no column for it here.
        validated_data.pop("reason", None)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            if order.effective_status != SalesOrder.Status.CONFIRMED or any(
                line.fulfilled_qty for line in order.items.all()
            ):
                raise SalesOrderEditRefused(
                    f"Sales order {order.order_no} is {order.effective_status} and "
                    "cannot be rewritten: only a CONFIRMED order with nothing "
                    "fulfilled can be edited. Cancel the remainder instead.",
                    status=order.effective_status,
                )
            delivery = order.deliveries.first()
            if (
                delivery_data is not None
                and delivery is not None
                and delivery.status != Delivery.Status.SCHEDULED
            ):
                raise SalesOrderEditRefused(
                    f"Delivery {delivery.delivery_no} is {delivery.status}: the slip "
                    "can only be corrected while it is still SCHEDULED.",
                    delivery_no=delivery.delivery_no,
                    delivery_status=delivery.status,
                )
            if "notes" in validated_data:
                order.notes = validated_data["notes"]
            order.save(update_fields=["notes", "updated_at"])
            if items is not None:
                lock_selling_unit_lines(
                    ((item["variant_uom"], item) for item in items),
                    document="sales order",
                )
                # Decision 19 #1 + B3 review: the approval is spent PER SAVE. A create-time
                # token was already consumed by the order that carried it, so re-pricing the
                # lines above the cap here needs a FRESH token - the old one is `used_at`.
                approval = guard_order_line_prices(
                    lines=((item["variant_uom"], item["unit_price"]) for item in items),
                    discount_approval=discount_approval,
                )
                order.items.all().delete()
                for item in items:
                    SalesOrderItem.objects.create(order=order, **item)
                if approval is not None:
                    approval.used_at = timezone.now()
                    approval.sales_order = order
                    approval.save(update_fields=["used_at", "sales_order"])
            if delivery_data is not None:
                from .services import _validated_delivery, create_delivery

                if delivery is None:
                    create_delivery(
                        data=delivery_data,
                        created_by=order.created_by,
                        sales_order=order,
                    )
                else:
                    # The SAME validation the create path uses: one definition of what
                    # a delivery is, so the form and the till cannot disagree.
                    fields = _validated_delivery(delivery_data) or {}
                    for name, value in fields.items():
                        setattr(delivery, name, value)
                    if fields:
                        delivery.save(update_fields=[*fields, "updated_at"])
        return order


class HeldCartItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = HeldCartItem
        fields = ["id", "cart", "variant_uom", "qty", "unit_price"]
        read_only_fields = ["id", "cart"]


class HeldCartSerializer(serializers.ModelSerializer):
    items = HeldCartItemSerializer(many=True, required=False)
    customer_name = serializers.CharField(
        source="customer.name", read_only=True, default=None
    )
    cashier_name = serializers.CharField(source="cashier.full_name", read_only=True)

    class Meta:
        model = HeldCart
        fields = [
            "id",
            "cashier",
            "cashier_name",
            "customer",
            "customer_name",
            "notes",
            "items",
            "created_at",
        ]
        read_only_fields = ["id", "cashier", "created_at"]

    def create(self, validated_data):
        items_data = validated_data.pop("items", [])
        # Phase 1d Task 2 (decision 16): the same whole-unit rule as the till, checked
        # BEFORE the cart row exists, so a refused hold leaves nothing behind.
        for index, item in enumerate(items_data, start=1):
            vuom = item["variant_uom"]
            refuse_fractional_whole_unit(
                is_whole=vuom.uom.is_whole,
                qty=item["qty"],
                what=f"Line {index} ({vuom.variant}, {vuom.uom.code})",
            )
        # Phase 1d Task 3: take the SAME row lock the removal action takes
        # (`VariantUOMViewSet.destroy`), before writing any line. A held-cart line
        # PROTECTs its selling unit, so the removal refuses a unit that is already held;
        # this lock is what makes "already held" true for a hold that is still being
        # saved. Without it the removal could delete the row between this cart's
        # validation and its INSERT, and the foreign key would answer a 500 instead of a
        # refusal the till can act on.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            lock_selling_unit_lines(
                ((item["variant_uom"], item) for item in items_data),
                document="held cart",
            )
            cart = HeldCart.objects.create(**validated_data)
            for item in items_data:
                HeldCartItem.objects.create(cart=cart, **item)
        return cart


class DeliverySerializer(serializers.ModelSerializer):
    """The delivery slip (Phase 5 task B3, decision 18).

    ONE shape for the list, the detail and the response of every status action, because
    the deliveries page renders the same card in all three places. The slip's `items`
    come from the SALE or the ORDER the delivery belongs to - the delivery itself has no
    lines: it is a trip for documents that already exist.

    `items[].qty` is the SELLING quantity (a box, a bag), the same number the receipt
    shows, `unit` is that selling unit's code, and `stored_at` / `stored_at_name` are the
    pick-up point the driver needs (Phase 5 B4, decision 18) - B3 left that spot for B4.
    """

    customer = serializers.SerializerMethodField()
    customer_name = serializers.SerializerMethodField()
    transaction_no = serializers.CharField(
        source="sale.transaction_no", read_only=True, default=None
    )
    order_no = serializers.CharField(
        source="sales_order.order_no", read_only=True, default=None
    )
    created_by_name = serializers.CharField(
        source="created_by.full_name", read_only=True
    )
    items = serializers.SerializerMethodField()

    class Meta:
        model = Delivery
        # Tuples, not lists: same reason as `DeliveryViewSet` - the file's other
        # serializers carry one RUF012 each for these two attributes.
        fields = (
            "id",
            "delivery_no",
            "sale",
            "sales_order",
            "transaction_no",
            "order_no",
            "customer",
            "customer_name",
            "address",
            "contact_name",
            "contact_phone",
            "scheduled_date",
            "fee",
            "status",
            "failure_reason",
            "items",
            "created_by",
            "created_by_name",
            "created_at",
            "updated_at",
        )
        # Every field is derived from a document the server already wrote: a delivery is
        # created by ringing a sale or creating an order, never by POSTing to
        # `/deliveries/`, and only `start/`, `deliver/` and `fail/` move it.
        read_only_fields = fields

    def get_customer(self, obj):
        if obj.sale_id:
            return obj.sale.customer_id
        return obj.sales_order.customer_id

    def get_customer_name(self, obj):
        if obj.sale_id:
            return obj.sale.customer.name
        return obj.sales_order.customer.name

    def get_items(self, obj):
        if obj.sale_id:
            rows = obj.sale.items.all()
        elif obj.sales_order_id:
            rows = obj.sales_order.items.all()
        else:
            return []
        # Phase 5 B4 (decision 18): each line names WHERE it is picked up. ONE query for
        # the whole slip - not one per line - for the rows' products and locations.
        stored_at = self._stored_at(rows)
        return [
            {
                "name": str(row.variant_uom.variant),
                "unit": row.variant_uom.uom.code,
                "qty": f"{row.qty:.2f}",
                "stored_at": stored_at.get(row.variant_uom_id, (None, None))[0],
                "stored_at_name": stored_at.get(row.variant_uom_id, (None, None))[1],
                # Phase 9 B2 (decision 21 §2): the driver is told the SPLIT - "3 at
                # Store, 2 at Bodega" - from the sale's deduction rows, read through
                # the viewset's prefetch so a slip of many lines still costs one query.
                "pick_up": pick_up_caption(
                    parts=self._parts(row),
                    fallback_location_id=stored_at.get(
                        row.variant_uom_id, (None, None)
                    )[0],
                    fallback_location_name=stored_at.get(
                        row.variant_uom_id, (None, None)
                    )[1],
                    qty=row.qty,
                    conversion_factor=row.variant_uom.conversion_factor,
                    selling_unit=row.variant_uom.uom.code,
                    base_unit=row.variant_uom.variant.base_uom.code,
                ),
            }
            for row in rows
        ]

    @staticmethod
    def _parts(row):
        """`[(location_id, location_name, base_qty)]` for a SALE line, in pick order.

        An ORDER line has no deductions - nothing has left the shelf yet - so it returns
        none and the caption falls back to the product's `stored_at`.
        """
        deductions = getattr(row, "deductions", None)
        if deductions is None:
            return []
        return [
            (row.batch.location_id, row.batch.location.name, row.qty)
            for row in deductions.all()
        ]

    @staticmethod
    def _stored_at(rows):
        """`{variant_uom_id: (location_id, location_name)}` in one query.

        Read through the selling unit's PRODUCT: a location labels a product, and its
        selling units inherit it, so the slip and the till line can never disagree.
        """
        from apps.inventory.models import VariantUOM

        unit_ids = {row.variant_uom_id for row in rows}
        return {
            unit_id: (location_id, location_name)
            for unit_id, location_id, location_name in (
                VariantUOM.objects.filter(pk__in=unit_ids).values_list(
                    "pk",
                    "variant__product__stored_at_id",
                    "variant__product__stored_at__name",
                )
            )
        }
