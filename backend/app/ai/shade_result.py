"""Per-zone shade fields: detected vs override stay separate.

effective_shade = override_shade if set else detected_shade.
Detection must never write override_shade; overrides never overwrite detected_shade.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ZoneShadeState:
    detected_shade: str | None = None
    delta_e_2000: float | None = None
    override_shade: str | None = None

    @property
    def effective_shade(self) -> str | None:
        if self.override_shade is not None:
            return self.override_shade
        return self.detected_shade

    @property
    def is_overridden(self) -> bool:
        return self.override_shade is not None


def apply_detection(
    state: ZoneShadeState,
    *,
    detected_shade: str,
    delta_e_2000: float,
) -> ZoneShadeState:
    """Re-run detection: refresh detected fields only; preserve override_shade."""
    return ZoneShadeState(
        detected_shade=detected_shade,
        delta_e_2000=delta_e_2000,
        override_shade=state.override_shade,
    )


def apply_override(state: ZoneShadeState, override_shade: str | None) -> ZoneShadeState:
    """Dentist override: set or clear override_shade; never touch detected fields."""
    return ZoneShadeState(
        detected_shade=state.detected_shade,
        delta_e_2000=state.delta_e_2000,
        override_shade=override_shade,
    )
