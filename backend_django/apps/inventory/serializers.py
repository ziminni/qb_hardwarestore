# pyright: reportAttributeAccessIssue=false
#
# Same directive and reason as apps/inventory/models.py and apps/inventory/views.py: the
# checker resolves its config from its WORKING DIRECTORY and does not run inside this
# repo, so pyrightconfig.json is not found and this travels with the file. Without
# django-stubs every `Model.objects` is a false positive on valid Django, and Django's own
# `manage.py check` plus the test run remain the authority on what this file does.
"""Inventory app — serializers for product catalog (Sprint 1)."""

from django.db import transaction
from rest_framework import serializers

from .exceptions import (
    BarcodeInvalid,
    BarcodeReservedPrefix,
    BarcodeTaken,
    DuplicateBaseUnit,
    InvalidPurchaseOrder,
    InvalidSellingUnit,
    InvalidVariant,
    SellingUnitInUse,
    SupplierInactive,
)
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    Supplier,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
    derived_code,
    gs1_check_digit,
    normalise_barcode,
)


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ['id', 'name', 'is_active', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ['id', 'name', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class UnitOfMeasureSerializer(serializers.ModelSerializer):
    class Meta:
        model = UnitOfMeasure
        fields = ['id', 'code', 'name', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


def selling_unit_is_sold(unit) -> bool:
    """True once a sale line or a held cart line references this selling unit.

    Why these two tables (Phase 4 Task 1): a `SalesItem` is money already taken and stock
    already deducted — changing the unit's factor or uom afterwards re-writes what the
    return cap and restock are measured against. A `HeldCartItem` is a parked cart that
    will be sold as it stands, so the same change would reprice or re-measure a cart a
    cashier is holding. Quotations and sales orders are DOCUMENTS priced on the day they
    were written and move no stock; they are deliberately not part of the guard.
    """
    from apps.pos.models import HeldCartItem, SalesItem

    return (
        SalesItem.objects.filter(variant_uom_id=unit.pk).exists()
        or HeldCartItem.objects.filter(variant_uom_id=unit.pk).exists()
    )


class VariantUOMSerializer(serializers.ModelSerializer):
    """A selling unit — the row the till prices a line from.

    `conversion_factor` and `default_selling_price` are declared EXPLICITLY, without the
    model's `MinValueValidator`s, because DRF copies those validators onto the generated
    field and they run before `validate()`: a factor of 0 answered
    `{"conversion_factor": ["Ensure this value is greater than or equal to 0.01."]}`, a
    dict no client can branch on. Declaring the two fields keeps the same refusal but in
    the project's stable `{code, detail}` shape (`INVALID_SELLING_UNIT`).
    """

    uom_code = serializers.CharField(source='uom.code', read_only=True)
    uom_name = serializers.CharField(source='uom.name', read_only=True)
    conversion_factor = serializers.DecimalField(max_digits=12, decimal_places=2)
    default_selling_price = serializers.DecimalField(max_digits=12, decimal_places=2)

    # Frozen once the unit has been sold: they decide what a past sale MEANT. The price
    # is deliberately absent — a shop reprices all the time and the sale line keeps its
    # own `unit_price`, so raising the price cannot corrupt history.
    FROZEN_ONCE_SOLD = ('variant', 'uom', 'conversion_factor')

    class Meta:
        model = VariantUOM
        fields = [
            'id', 'variant', 'uom', 'uom_code', 'uom_name',
            'barcode_qr', 'conversion_factor', 'default_selling_price',
        ]
        read_only_fields = ['id']

    def validate_barcode_qr(self, value):
        """One normalised, check-digit-valid, unclaimed code per selling unit.

        Decisions 11/12: trim + upper so a stored code equals a scanned one; printable
        ASCII without spaces so it can be printed and read; a GS1 check digit on an
        all-digit 8/12/13-character manufacturer code so a keying typo is caught before
        the label is trusted; `QB` reserved for codes the server derives itself.

        An empty value is ALLOWED and returned empty: the model's `save()` then derives
        this unit's own `QB` code (decision 16), which is what makes a PATCH of `''` a
        restore rather than an unscannable row.
        """
        code = normalise_barcode(value)
        if not code:
            return ''

        if len(code) > 100 or not all(33 <= ord(char) < 127 for char in code):
            raise BarcodeInvalid(
                'barcode_qr must be printable ASCII without spaces or control '
                'characters, at most 100 characters: a code is printed and read by a '
                'scanner, so it has to survive both.')

        if code.isdigit() and len(code) in (8, 12, 13):
            expected = gs1_check_digit(code[:-1])
            if expected != int(code[-1]):
                raise BarcodeInvalid(
                    f'{code} fails the GS1 check digit: the last digit should be '
                    f'{expected}. Re-read the number on the package.')

        if code.startswith('QB'):
            own = derived_code(self.instance.pk) if self.instance is not None else None
            if code != own:
                detail = f'{code} is refused: "QB" codes are generated by the server.'
                raise BarcodeReservedPrefix(
                    f'{detail} This unit\'s own code is {own}.' if own else
                    f'{detail} A new selling unit is given its own code automatically.')

        holder = self._barcode_holder(code)
        if holder is not None:
            raise BarcodeTaken(
                f'{code} is already the code of {holder.variant.product.base_name} · '
                f'{holder.variant.variant_name} · {holder.uom.code}. A code is what a '
                'scan resolves to, so one unit per code.')

        return code

    def _barcode_holder(self, code):
        """The OTHER selling unit already holding `code`, case-insensitively.

        Only a readable refusal - the DB constraint is the real guard, because this read
        and the write are not one atomic step (see `VariantUOMViewSet`).
        """
        rivals = VariantUOM.objects.filter(barcode_qr__iexact=code)
        if self.instance is not None:
            rivals = rivals.exclude(pk=self.instance.pk)
        return rivals.select_related('variant__product', 'uom').first()

    def validate(self, attrs):
        variant = attrs.get('variant')
        if variant is None and self.instance is not None:
            variant = self.instance.variant
        factor = attrs.get('conversion_factor')
        if factor is None and self.instance is not None:
            factor = self.instance.conversion_factor
        price = attrs.get('default_selling_price')
        if price is None and self.instance is not None:
            price = self.instance.default_selling_price

        if factor is not None and factor <= 0:
            raise InvalidSellingUnit(
                'conversion_factor must be greater than 0: it is how many base units '
                'one selling unit is, and a sale multiplies by it.')
        if price is not None and price < 0:
            raise InvalidSellingUnit(
                'default_selling_price must not be negative.')

        if factor is not None and factor == 1 and variant is not None:
            # Factor 1 IS the base unit. Checked on create and whenever the factor is
            # written, so an unrelated PATCH cannot re-open the ambiguity either.
            rivals = VariantUOM.objects.filter(
                variant=variant, conversion_factor=1)
            if self.instance is not None:
                rivals = rivals.exclude(pk=self.instance.pk)
            if rivals.exists():
                raise DuplicateBaseUnit(
                    f'{variant} already has a conversion-factor-1 selling unit: a '
                    'variant has exactly one base unit.')

        if self.instance is not None:
            changed = [
                field for field in self.FROZEN_ONCE_SOLD
                if field in attrs
                and _field_value(attrs[field])
                != _field_value(getattr(self.instance, field))
            ]
            if changed and selling_unit_is_sold(self.instance):
                raise SellingUnitInUse(
                    f'{self.instance} has been sold: {', '.join(changed)} cannot be '
                    'changed without rewriting what past sales and returns mean. '
                    'Create a new selling unit; the price stays editable.')

        return attrs


def _field_value(value):
    """A comparable key for a validated field: an FK instance compares by its pk."""
    return getattr(value, 'pk', value)


class ProductVariantSerializer(serializers.ModelSerializer):
    """A variant. Thresholds may not go negative; product/base_uom are set once.

    Both thresholds are declared explicitly for the same reason as the selling unit's
    factor: the model's `MinValueValidator(0)` fired first and answered with DRF's
    field-error dict instead of the project's `INVALID_VARIANT` code.
    """

    base_uom_code = serializers.CharField(
        source='base_uom.code', read_only=True)
    selling_uoms = VariantUOMSerializer(many=True, read_only=True)
    min_stock_threshold = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False)
    max_stock_level = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False)

    class Meta:
        model = ProductVariant
        fields = [
            'id', 'product', 'variant_name', 'base_uom',
            'base_uom_code', 'min_stock_threshold', 'max_stock_level',
            'is_active', 'selling_uoms', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    # Set at creation: stock batches, sale deductions and every historical figure hang
    # off these two, so re-pointing them would rewrite the variant's whole history.
    FROZEN_AFTER_CREATION = ('product', 'base_uom')

    def validate(self, attrs):
        for field in ('min_stock_threshold', 'max_stock_level'):
            value = attrs.get(field)
            if value is not None and value < 0:
                raise InvalidVariant(f'{field} must not be negative.')

        if self.instance is not None:
            for field in self.FROZEN_AFTER_CREATION:
                if field not in attrs:
                    continue
                if _field_value(attrs[field]) != _field_value(
                        getattr(self.instance, field)):
                    raise InvalidVariant(
                        f'{field} is set when the variant is created: changing it '
                        'would re-point its stock and sales history.')

        return attrs


class ProductSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(
        source='category.name', read_only=True)
    brand_name = serializers.CharField(
        source='brand.name', read_only=True)
    variants = ProductVariantSerializer(many=True, read_only=True)

    class Meta:
        model = Product
        fields = [
            'id', 'category', 'category_name', 'brand', 'brand_name',
            'base_name', 'description', 'image_url', 'is_active',
            'variants', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
class SupplierSerializer(serializers.ModelSerializer):
    class Meta:
        model = Supplier
        fields = ['id','company_name','contact_person','phone','email','address','is_active','created_at','updated_at']
        read_only_fields = ['id','created_at','updated_at']


class POItemSerializer(serializers.ModelSerializer):
    """One purchase-order line — a NESTED write, because there is no `/po-items/` endpoint.

    `po` is read-only: the parent serializer creates the lines under the order it is
    building, so a client sending a `po` here was sending a value that was then
    overwritten. `received_qty` is read-only for the same reason and a stronger one — it
    is the running total the goods-receipt path accumulates under a lock (Task 6B.2), and
    a client-writable one would let a delivery be claimed without stock moving.

    `ordered_qty` / `unit_cost` are declared WITHOUT the model's validators so the
    refusal is the project's `INVALID_PO` code instead of DRF's field-error dict.
    """

    variant_name = serializers.CharField(source='variant.variant_name', read_only=True)
    ordered_qty = serializers.DecimalField(max_digits=12, decimal_places=2)
    unit_cost = serializers.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        model = POItem
        fields = ['id','po','variant','variant_name','ordered_qty','unit_cost','received_qty']
        read_only_fields = ['id','po','received_qty']

    def validate(self, attrs):
        qty = attrs.get('ordered_qty')
        if qty is None or qty <= 0:
            raise InvalidPurchaseOrder(
                'ordered_qty must be greater than 0: a line for nothing is not an order.')
        cost = attrs.get('unit_cost')
        if cost is None or cost < 0:
            raise InvalidPurchaseOrder('unit_cost must not be negative.')
        variant = attrs.get('variant')
        if variant is not None and not variant.is_active:
            raise InvalidPurchaseOrder(
                f'{variant} is inactive: it cannot be ordered until it is restored.')
        return attrs


class PurchaseOrderSerializer(serializers.ModelSerializer):
    """A purchase order with its lines as a nested write (Phase 4 Task 2).

    `status` is READ-ONLY and the transitions are actions (`place/`, `cancel/`), for the
    same reason `/requisitions/` works that way: placing an order is an event with an
    audit row and a supplier conversation behind it, not a field a PATCH may set.
    `created_by` is the caller, assigned in the view from `request.user`.
    """

    items = POItemSerializer(many=True, required=False)
    created_by_name = serializers.CharField(source='created_by.full_name', read_only=True)

    class Meta:
        model = PurchaseOrder
        fields = ['id','supplier','created_by','created_by_name','order_date','expected_delivery','status','notes','items','created_at','updated_at']
        read_only_fields = ['id','created_by','order_date','status','created_at','updated_at']

    def validate(self, attrs):
        supplier = attrs.get('supplier')
        if supplier is None and self.instance is not None:
            supplier = self.instance.supplier
        if supplier is None:
            raise InvalidPurchaseOrder('a purchase order needs a supplier.')
        if not supplier.is_active:
            raise SupplierInactive(supplier)

        if 'items' in attrs:
            lines = attrs['items'] or []
            if not lines:
                raise InvalidPurchaseOrder(
                    'a purchase order needs at least one line.')
            seen = {}
            for line in lines:
                variant = line['variant']
                if variant.pk in seen:
                    raise InvalidPurchaseOrder(
                        f'{variant} appears twice: an order carries one line per '
                        'variant (raise its quantity instead).')
                seen[variant.pk] = True
        elif self.instance is None:
            raise InvalidPurchaseOrder(
                'a purchase order needs at least one line.')

        return attrs

    def create(self, validated_data):
        lines = validated_data.pop('items')
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = PurchaseOrder.objects.create(**validated_data)
            POItem.objects.bulk_create(
                [POItem(po=po, **line) for line in lines])
        return po

    def update(self, instance, validated_data):
        lines = validated_data.pop('items', None)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = super().update(instance, validated_data)
            if lines is not None:
                # Replaced wholesale: keeping the old rows would leave an order whose
                # lines nobody asked for. Only reachable while DRAFT (the viewset refuses
                # the PATCH otherwise), so no receipt can be PROTECT-ing a line here.
                po.items.all().delete()
                POItem.objects.bulk_create(
                    [POItem(po=po, **line) for line in lines])
        return po
class InventoryBatchSerializer(serializers.ModelSerializer):
    class Meta:
        model = InventoryBatch
        fields = ['id','variant','receipt','initial_qty','current_qty','unit_cost_landed','markup_percentage','batch_selling_price','expiration_date','created_at']
        read_only_fields = ['id','created_at']


class GoodsReceiptItemSerializer(serializers.ModelSerializer):
    """One delivered line. Read-only: lines are created by the receipt POST itself.

    `variant`/`variant_name` are here because a receiving screen has to label the line
    without a second request per po_item, and the po_item id alone does not say what was
    delivered. `qty` is the quantity THIS receipt delivered, not the running total.
    """

    variant = serializers.IntegerField(source='po_item.variant_id', read_only=True)
    variant_name = serializers.CharField(
        source='po_item.variant.variant_name', read_only=True)

    class Meta:
        model = GoodsReceiptItem
        fields = ['id', 'po_item', 'variant', 'variant_name', 'qty']
        read_only_fields = fields


class GoodsReceiptSerializer(serializers.ModelSerializer):
    batches = InventoryBatchSerializer(many=True, read_only=True)
    lines = GoodsReceiptItemSerializer(many=True, read_only=True)
    received_by_name = serializers.CharField(source='received_by.full_name', read_only=True)
    class Meta:
        model = GoodsReceipt
        fields = ['id','po','received_by','received_by_name','receive_date','delivery_receipt_no','notes','lines','batches','processed_at','created_at']
        # `received_by` is READ-ONLY: the actor is not the client's to choose. The viewset
        # already passes `request.user` into creation, so a writable `received_by` was
        # demanded by validation and then had to be sent — every client had to supply a
        # value that means nothing. Same invariant as the checkout's `cashier` field.
        # `processed_at` is read-only for the same reason the timestamp is: the server's
        # process/ call sets it, and a client-writable one would let a caller mark a
        # receipt done (or un-done) without any stock moving.
        read_only_fields = ['id','received_by','receive_date','processed_at','created_at']


class StockAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockAdjustment
        fields = ['id','variant','user','adjustment_type','qty_adjusted','remarks','timestamp']
        # `user` is READ-ONLY because the actor is never the client's to choose.
        # StockAdjustmentViewSet.perform_create already does
        # `serializer.save(user=self.request.user)`, so a writable `user` was
        # both demanded by validation and then discarded -- every client was
        # forced to send a value that had no effect, and a client could have
        # attributed an adjustment to somebody else. Found by POSTing this
        # endpoint's real body to the running server: HTTP 400
        # {"user":["This field is required."]}.
        read_only_fields = ['id','timestamp','user']

    def validate_qty_adjusted(self, value):
        # A zero adjustment is not a correction, it is a no-op with a receipt: a
        # StockAdjustment row is the stock ledger's evidence that quantity moved, so a row
        # that moved nothing is a false record. Refused HERE rather than in the service
        # because it is a payload fact (sign is meaningful, magnitude must be non-zero)
        # and DRF turns it into the same 400 the other validation errors use.
        if value == 0:
            raise serializers.ValidationError(
                'qty_adjusted must not be 0: an adjustment records stock that moved, '
                'and use a negative value for a removal.')
        return value


class SystemAlertSerializer(serializers.ModelSerializer):
    """An alert raised by the system, plus who cleared it and when.

    `resolved_by_name` is derived rather than stored (expressive-dev rule: one home per
    fact) and prefers the human `full_name`, falling back to the username because a
    seeded account may have a blank full name.
    """

    resolved_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SystemAlert
        # Every field is read-only: alerts are system-generated and the only write the
        # API accepts is POST /alerts/{id}/resolve/ (decision 06), which sets the trail
        # from `request.user` and the server clock - never from the payload.
        fields = [
            'id', 'alert_type', 'variant', 'message', 'is_resolved',
            'resolved_by', 'resolved_by_name', 'resolved_at', 'created_at',
        ]
        read_only_fields = fields

    def get_resolved_by_name(self, alert):
        resolver = alert.resolved_by
        if resolver is None:
            return None
        return resolver.full_name or resolver.username

