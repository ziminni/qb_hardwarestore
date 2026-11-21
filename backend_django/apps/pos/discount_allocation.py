def allocate_discounts(
    lines: list[tuple[int, int, bool]], cart_discount: int
) -> list[int]:
    """Return each line's cart discount in centavos, in input order.

    Each line provides gross centavos, applied item discount centavos, and cart
    eligibility. Equal fractional remainders are resolved in input order.
    """
    weights = []
    for gross, item_discount, eligible in lines:
        if not 0 <= item_discount <= gross:
            raise ValueError("Item discount must be between zero and its line gross.")
        weights.append(gross - item_discount if eligible else 0)

    total = sum(weights)
    if not 0 <= cart_discount <= total:
        raise ValueError("Cart discount must be between zero and the eligible balance.")
    if cart_discount == 0:
        return [0] * len(lines)

    shares = [divmod(cart_discount * weight, total) for weight in weights]
    amounts = [amount for amount, _ in shares]
    leftover = cart_discount - sum(amounts)
    ranked = sorted(range(len(shares)), key=lambda index: -shares[index][1])
    for index in ranked[:leftover]:
        amounts[index] += 1
    return amounts
