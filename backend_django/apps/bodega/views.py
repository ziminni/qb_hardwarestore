# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""Bodega endpoints (decision 25; ENDPOINTS.md §3.8).

Everything: `IsBodegaRole` (Bodega Checker, Stock Manager, Store Manager, Admin). The
checker only reads and confirms: stock moves in through the stocker's Receiving (held
here until checked) and out at the till.
"""

from collections import defaultdict
from typing import Any, cast

from django.core.cache import cache
from django.db import transaction
from django.db.models import Q
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.inventory.models import ProductVariant, StorageLocation
from apps.pos.models import SalesTransaction
from apps.users.models import AuditLog
from apps.users.permissions import IsBodegaRole
from apps.users.photos import checked_photo
from apps.users.services import audit_request

from . import services
from .exceptions import InvalidBodegaDelivery
from .models import BodegaDelivery, BodegaDeliveryLine, BodegaRelease
from .serializers import (
    BodegaDeliverySerializer,
    BodegaReleaseSerializer,
    DeliveryConfirmInput,
    ReleaseInput,
)


def _claims_payload(lines):
    """Group derived claim lines into one object per sale, newest sale first."""
    if not lines:
        return []
    sale_ids = {line["sale_id"] for line in lines}
    sales = SalesTransaction.objects.select_related(
        "customer", "receipt", "cashier"
    ).in_bulk(sale_ids)
    variants = ProductVariant.objects.select_related("product", "base_uom").in_bulk(
        {line["variant_id"] for line in lines}
    )
    locations = StorageLocation.objects.in_bulk({line["location_id"] for line in lines})
    grouped = defaultdict(list)
    for line in lines:
        variant = variants[line["variant_id"]]
        grouped[line["sale_id"]].append(
            {
                "variant": variant.pk,
                "label": f"{variant.product.base_name} — {variant.variant_name}",
                "unit": variant.base_uom.code,
                "location": line["location_id"],
                "location_name": locations[line["location_id"]].name,
                "sold": line["sold"],
                "released": line["released"],
                "remaining": line["remaining"],
            }
        )
    import secrets

    from apps.pos.models import Delivery
    from apps.sms.models import BodegaSmsTicket

    tickets_by_sale = {
        t.sale_id: t.code
        for t in BodegaSmsTicket.objects.filter(sale_id__in=grouped.keys()).only(
            "sale_id", "code"
        )
    }
    deliveries_by_sale = {}
    for d in Delivery.objects.filter(sale_id__in=grouped.keys()):
        deliveries_by_sale[d.sale_id] = d
    # Also check order-linked deliveries for partial/later order fulfilments
    missing_sale_ids = set(grouped.keys()) - set(deliveries_by_sale.keys())
    if missing_sale_ids:
        for sale_id_row, order_id in (
            SalesTransaction.objects.filter(
                pk__in=missing_sale_ids,
                items__order_line__order_id__isnull=False,
            )
            .values_list("pk", "items__order_line__order_id")
            .distinct()
        ):
            d = Delivery.objects.filter(sales_order_id=order_id).first()
            if d is not None:
                deliveries_by_sale[sale_id_row] = d

    out = []
    for sale_id, sale_lines in grouped.items():
        sale = sales[sale_id]
        sale_lines.sort(key=lambda row: row["label"])
        remaining = sum((row["remaining"] for row in sale_lines), services.ZERO)
        receipt = getattr(sale, "receipt", None)
        delivery = deliveries_by_sale.get(sale.pk)
        is_delivery = delivery is not None
        # A delivery that was already marked DELIVERED or FAILED in Deliveries is no longer
        # waiting at the Bodega gate to be loaded.
        delivery_finished = is_delivery and delivery.status in (
            Delivery.Status.DELIVERED,
            Delivery.Status.FAILED,
        )
        is_open = remaining > 0 and not delivery_finished
        sms_code = tickets_by_sale.get(sale.pk, "")
        if is_open and not sms_code:
            ticket, _ = BodegaSmsTicket.objects.get_or_create(
                sale=sale,
                defaults={"code": f"{secrets.randbelow(10000):04d}"},
            )
            sms_code = ticket.code
        out.append(
            {
                "sale": sale.pk,
                "transaction_no": sale.transaction_no,
                "or_number": receipt.or_number if receipt else "",
                "sms_code": sms_code,
                "customer_name": sale.customer.name if sale.customer_id else "",
                "sold_at": sale.trans_date,
                "is_open": is_open,
                "remaining_total": remaining,
                "is_delivery": is_delivery,
                "delivery_no": delivery.delivery_no if delivery else "",
                "delivery_status": delivery.status if delivery else "",
                "delivery_address": delivery.address if delivery else "",
                "lines": sale_lines,
            }
        )
    out.sort(key=lambda row: row["sold_at"], reverse=True)
    return out


class BodegaStockView(APIView):
    """`GET /bodega/stock/` — books, paid-not-collected and physical, per Bodega shelf."""

    permission_classes = [IsBodegaRole]

    def get(self, request):
        return Response(services.bodega_stock())


class BodegaClaimListView(APIView):
    """`GET /bodega/claims/?open=true&q=` — receipts with Bodega goods.

    `open` defaults to true (only receipts with something left to collect). `q` matches
    the transaction number, the OR number or the customer's name.
    """

    permission_classes = [IsBodegaRole]

    def get(self, request):
        only_open = request.query_params.get("open", "true").lower() != "false"
        query = request.query_params.get("q", "").strip()
        sale_ids = None
        if query:
            sale_ids = list(
                SalesTransaction.objects.filter(
                    Q(
                        Q(transaction_no__icontains=query),
                        Q(receipt__or_number__icontains=query),
                        Q(customer__name__icontains=query),
                        _connector=Q.OR,
                    )
                ).values_list("pk", flat=True)[:200]
            )
        claims = _claims_payload(services.claim_lines(sale_ids, include_dispatch=True))
        if only_open:
            claims = [claim for claim in claims if claim["is_open"]]
        return Response(claims)


class BodegaClaimLookupView(APIView):
    """`GET /bodega/claims/lookup/?receipt=` — one receipt's claim, open or not."""

    permission_classes = [IsBodegaRole]

    def get(self, request):
        sale = services.find_sale(request.query_params.get("receipt", ""))
        claims = _claims_payload(services.claim_lines([sale.pk], include_dispatch=True))
        if not claims:
            raise services.NoBodegaClaim(
                f"Sale {sale.transaction_no} took nothing from the Bodega, so there is "
                "nothing to release here."
            )
        payload = claims[0]
        payload["releases"] = BodegaReleaseSerializer(
            sale.bodega_releases.select_related(
                "checker", "sale__customer"
            ).prefetch_related(
                "lines__variant__product", "lines__variant__base_uom", "lines__location"
            ),
            many=True,
        ).data
        return Response(payload)


class BodegaReleaseViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet
):
    """`/bodega/releases/` — the hand-over log (newest first) and `POST` to release.

    Append-only: a release is the record that goods left; there is no edit or delete.
    """

    permission_classes = [IsBodegaRole]
    serializer_class = BodegaReleaseSerializer

    def get_queryset(self):
        rows = BodegaRelease.objects.select_related(
            "checker", "sale", "sale__customer"
        ).prefetch_related(
            "lines__variant__product", "lines__variant__base_uom", "lines__location"
        )
        query = self.request.query_params.get("q", "").strip()
        if query:
            rows = rows.filter(
                Q(
                    Q(number__icontains=query),
                    Q(sale__transaction_no__icontains=query),
                    Q(received_by__icontains=query),
                    Q(plate_no__icontains=query),
                    _connector=Q.OR,
                )
            )
        return rows

    def create(self, request):
        idem_key = (request.headers.get("Idempotency-Key") or "").strip()[:64]
        cache_key = (
            f"bodega_release_idem:{request.user.pk}:{idem_key}" if idem_key else ""
        )
        if cache_key:
            cached_id = cache.get(cache_key)
            if cached_id is not None:
                existing = self.get_queryset().filter(pk=cached_id).first()
                if existing is not None:
                    return Response(
                        BodegaReleaseSerializer(existing).data,
                        status=status.HTTP_200_OK,
                    )

        data = ReleaseInput(data=request.data)
        data.is_valid(raise_exception=True)
        body = cast(dict[str, Any], data.validated_data)
        with transaction.atomic():
            sale = services.find_sale(body["receipt"])
            release = services.record_release(
                sale=sale,
                checker=request.user,
                received_by=body["received_by"],
                plate_no=body.get("plate_no", ""),
                notes=body.get("notes", ""),
                lines=[
                    (line["variant"], line["location"], line["qty"])
                    for line in body["lines"]
                ],
            )
            audit_request(
                request,
                AuditLog.ActionType.RELEASE,
                f"Bodega release {release.number} against {sale.transaction_no}: "
                f"{len(body['lines'])} line(s) to {release.received_by}"
                + (f", truck {release.plate_no}" if release.plate_no else "")
                + ".",
            )
        if cache_key:
            cache.set(cache_key, release.pk, timeout=86400)
        release = self.get_queryset().get(pk=release.pk)
        return Response(
            BodegaReleaseSerializer(release).data, status=status.HTTP_201_CREATED
        )


class BodegaDeliveryViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet
):
    """`/bodega/deliveries/` — supplier deliveries to the Bodega and the checker's verdict.

    The stocker records the delivery in Receiving; its Bodega lines wait here as
    `PENDING` until `POST …/{id}/confirm/` says how much arrived good and damaged.
    """

    permission_classes = [IsBodegaRole]
    serializer_class = BodegaDeliverySerializer

    def get_queryset(self):
        rows = BodegaDelivery.objects.select_related(
            "location", "checked_by", "receipt__received_by", "receipt__po__supplier"
        ).prefetch_related("lines__variant__product", "lines__variant__base_uom")
        wanted = self.request.query_params.get("status", "").strip().upper()
        if wanted:
            rows = rows.filter(status=wanted)
        return rows

    @action(detail=True, methods=["post"])
    def confirm(self, request, pk=None):
        data = DeliveryConfirmInput(data=request.data)
        data.is_valid(raise_exception=True)
        body = cast(dict[str, Any], data.validated_data)
        with transaction.atomic():
            delivery = services.confirm_delivery(
                delivery_id=pk,
                checker=request.user,
                notes=body.get("notes", ""),
                lines={
                    line["line"]: (
                        line["good_qty"],
                        line["damaged_qty"],
                        line.get("remarks", ""),
                    )
                    for line in body["lines"]
                },
            )
            damaged = sum(
                (row.damaged_qty for row in delivery.lines.all()), services.ZERO
            )
            audit_request(
                request,
                AuditLog.ActionType.RECEIPT,
                f"Bodega delivery {delivery.number} checked at {delivery.location.name}: "
                f"{delivery.lines.count()} line(s), {damaged} damaged written off.",
            )
        return Response(
            BodegaDeliverySerializer(
                self.get_queryset().get(pk=delivery.pk),
                context=self.get_serializer_context(),
            ).data
        )

    @action(
        detail=True,
        methods=["post"],
        url_path=r"lines/(?P<line_id>\d+)/photo",
        parser_classes=[MultiPartParser],
    )
    def line_photo(self, request, pk=None, line_id=None):
        """`POST …/{id}/lines/{line_id}/photo/` (multipart `photo`): the item's proof.

        Only while the delivery waits for checking: the photo is taken as the item is
        checked, before the verdict. A second photo replaces the first; the old file
        is deleted once the new one is committed.
        """
        photo = checked_photo(request.FILES.get("photo"))
        with transaction.atomic():
            line = (
                BodegaDeliveryLine.objects.select_for_update()
                .select_related("delivery")
                .filter(pk=line_id, delivery_id=pk)
                .first()
            )
            if line is None:
                raise InvalidBodegaDelivery(f"Delivery #{pk} has no line #{line_id}.")
            if line.delivery.status != BodegaDelivery.Status.PENDING:
                raise InvalidBodegaDelivery(
                    f"{line.delivery.number} was already checked; its photos are final."
                )
            previous = line.photo.name if line.photo else ""
            storage = line.photo.storage
            line.photo = photo
            line.save(update_fields=["photo"])
            if previous:
                transaction.on_commit(lambda: storage.delete(previous))
        return Response(
            BodegaDeliverySerializer(
                self.get_queryset().get(pk=pk),
                context=self.get_serializer_context(),
            ).data
        )
