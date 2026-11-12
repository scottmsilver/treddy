"""The save-to-cart step must refuse anything but a clean, bounded quote."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import jlc_quote  # noqa: E402


def clean() -> dict:
    return {"warnings": [], "parts_confirmed": 82, "parts_detected": 82, "charges": {"Total Price": 270.16}}


def test_clean_quote_under_the_limit_may_be_saved():
    assert jlc_quote.cart_refusal(clean(), 300.0, 0) is None


@pytest.mark.parametrize(
    "change, limit, rotation, reason",
    [
        ({"warnings": ["JLC did not confirm every part"]}, 300.0, 0, "warnings"),
        ({"parts_confirmed": 81}, 300.0, 0, "81 of 82"),
        ({"parts_confirmed": None, "parts_detected": None}, 300.0, 0, "None of None"),
        ({}, 270.15, 0, "over the limit"),
        ({}, float("nan"), 0, "not a number"),
        ({"charges": {}}, 300.0, 0, "no total price"),
        ({"charges": {"Total Price": 273.66, "Hand-soldering labor fee": 3.5}}, 300.0, 0, "Hand-soldering"),
        ({}, 300.0, 1, "jlc_rotation_check"),
    ],
)
def test_anything_else_is_refused(change, limit, rotation, reason):
    assert reason in jlc_quote.cart_refusal({**clean(), **change}, limit, rotation)


def test_hand_solder_charge_and_missing_total_become_warnings():
    result = {"warnings": [], "charges": {"Hand-soldering labor fee": 3.5}}
    jlc_quote.charge_warnings(result)
    assert len(result["warnings"]) == 2


def test_cart_flags_go_together_and_reject_a_substitute_placement_file(tmp_path):
    for argv in (
        ["quote", "--out", str(tmp_path), "--save-to-cart"],
        ["quote", "--out", str(tmp_path), "--max-total", "300"],
        ["quote", "--out", str(tmp_path), "--save-to-cart", "--max-total", "nan"],
        ["quote", "--out", str(tmp_path), "--save-to-cart", "--max-total", "300", "--cpl", str(tmp_path / "x.csv")],
    ):
        with pytest.raises(SystemExit):
            jlc_quote.main(argv)


def test_ordinary_clicks_still_refuse_ordering_controls():
    for label in ("SAVE TO CART", "Secure Checkout", "Pay now", "Place Order"):
        assert jlc_quote.FORBIDDEN.search(label)
    assert jlc_quote.SAVE_TO_CART_LABEL.match(" Save to Cart ")
    assert not jlc_quote.SAVE_TO_CART_LABEL.match("Secure Checkout")
