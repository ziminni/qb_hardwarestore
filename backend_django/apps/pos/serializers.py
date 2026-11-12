# pyright: reportAttributeAccessIssue=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/models.py and apps/pos/services.py: the checker
# resolves its config from its WORKING DIRECTORY, so no pyrightconfig.json is found, and
# `Model.objects` is a false positive on valid Django without django-stubs.
from django.db import transaction
from rest_framework import serializers

from apps.inventory.services import lock_selling_unit_lines
from common.exceptions import refuse_fractional_whole_unit

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
    """One sale line, with where its product is kept (Phase 5 B4, decision 18).

    `stored_at` / `stored_at_name` are the product's label, read-only: a sale line does
    not choose a shelf, it reports the one the product has, so the receipt can print
    "Pick up at Bodega" without a second request per line.

    `stored_at_name` prefers an annotation the VIEW attached (`getattr(obj, ...)`, the
    same pattern as `VariantUOMSerializer.get_in_use`) and otherwise walks the relation.
    The walk costs a query per line when a list serializer has not joined
    `variant_uom__variant__product__stored_at`; that join lives in `apps/pos/views.py`,
    which this task may not edit, so the annotation path is the one a view should use.
    """

    variant_uom_code = serializers.CharField(
        source="variant_uom.uom.code", read_only=True
    )
    stored_at = serializers.IntegerField(
        source="variant_uom.variant.product.stored_at_id", read_only=True
    )
    stored_at_name = serializers.SerializerMethodField()

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
        ]
        read_only_fields = ["id", "subtotal"]

    def get_stored_at_name(self, obj):
        annotated = getattr(obj, "stored_at_name", None)
        if annotated is not None:
            return annotated
        return obj.variant_uom.variant.product.stored_at.name


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
        # Phase 1d Task 2 (decision 16, Q1): a quote is a promise to sell, so it carries the
        # same whole-unit rule as the till - a document that cannot be rung is not a quote.
        vuom = attrs.get("variant_uom")
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
        # either could forge a number or attribute a quotation to someone else.
        read_only_fields = ["id", "quotation_no", "created_at", "updated_at"]

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
    class Meta:
        model = SalesOrderItem
        fields = ["id", "order", "variant_uom", "qty", "unit_price"]
        # `order` is read-only for the same reason `quotation` is on the item serializer above:
        # the parent's create() sets it, and leaving it writable makes it REQUIRED on every nested
        # item, rejecting a legitimate payload.
        read_only_fields = ["id", "order"]

    def validate(self, attrs):
        # Same rule as a quotation: an order is what the shop promised to deliver.
        vuom = attrs.get("variant_uom")
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
    # Phase 5 task B3 (decision 18): an order may be marked Deliver. WRITE-ONLY and a
    # plain object, NOT a nested ModelSerializer: the delivery's rules (address, contact,
    # date, a fee in whole centavos) live in ONE place - `services._validated_delivery` -
    # so the order form and the till cannot disagree about what a delivery is.
    delivery = serializers.DictField(write_only=True, required=False)

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
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "order_no", "created_at", "updated_at"]

    def create(self, validated_data):
        items = validated_data.pop("items", [])
        delivery_data = validated_data.pop("delivery", None)
        # Same rule, lock and single transaction as a quotation above.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            lock_selling_unit_lines(
                ((item["variant_uom"], item) for item in items), document="sales order"
            )
            order = SalesOrder.objects.create(**validated_data)
            for item in items:
                SalesOrderItem.objects.create(order=order, **item)
            # Phase 5 task B3: the delivery row commits or rolls back WITH the order.
            # The fee stays on this row: an order carries no money total on the wire and
            # there is no fulfil-to-sale path in this codebase to carry it into.
            if delivery_data is not None:
                from .services import create_delivery

                order.delivery = create_delivery(
                    data=delivery_data, created_by=order.created_by, sales_order=order
                )
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
        # the whole slip - not one per line - because the rows' products are not joined
        # by the viewset's prefetch (that string lives in `apps/pos/views.py`, which this
        # task does not own) and a slip can carry many lines.
        stored_at = self._stored_at(rows)
        return [
            {
                "name": str(row.variant_uom.variant),
                "unit": row.variant_uom.uom.code,
                "qty": f"{row.qty:.2f}",
                "stored_at": stored_at.get(row.variant_uom_id, (None, None))[0],
                "stored_at_name": stored_at.get(row.variant_uom_id, (None, None))[1],
            }
            for row in rows
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
