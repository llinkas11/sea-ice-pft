"""
Shared constants and helpers for the rf_exploring3 figure scripts.

Eliminates duplicated PFT_COLORS / BLOCK_COLORS / block_of() / PRETTY label
dicts across the build_*.py scripts. Import from this module instead of
re-defining inline.

Usage:
    import sys; sys.path.insert(0, "/tmp")
    from figlib import (
        DOCS_DIR,
        PFT_COLORS, PFT_DISPLAY_ORDER,
        BLOCK_COLORS, block_of,
        PRETTY, short_label,
        FEATURES_OCEAN, FEATURES_LOCAL_ICE, FEATURES_EXPORT,
        FEATURES_ATM, FEATURES_SPATIAL, FEATURES_ALL,
    )
"""
from pathlib import Path

DOCS_DIR = Path("/Users/llinkas/Library/CloudStorage/OneDrive-BowdoinCollege/Desktop/RiO/docs")

# Display order matters for legends and overlays — kept consistent with the
# rf_utils.R PFT_COLORS so figures from the R and Python pipelines align.
PFT_DISPLAY_ORDER = ["Coccolithophores", "Diatoms", "Phaeocystis"]

PFT_COLORS = {
    "Coccolithophores": "#E69F00",
    "Diatoms":          "#56B4E9",
    "Phaeocystis":      "#009E73",
}

BLOCK_COLORS = {
    "ocean":   "#2E86AB",
    "ice":     "#A23B72",
    "export":  "#F18F01",
    "atm":     "#C73E1D",
    "spatial": "#5D5C61",
}

# Predictor block membership — single source of truth for which feature
# belongs to which block. Mirrors P3_*_VARS in rf_utils.R and probe_utils.py.
FEATURES_OCEAN     = ("thetao", "so", "mlotst")
FEATURES_LOCAL_ICE = ("siconc", "sithick", "siconc_lag1", "sithick_lag1")
FEATURES_EXPORT    = (
    "ice_area_flux_current",   "ice_area_flux_lag1",
    "ice_area_flux_lag2",      "ice_area_flux_cumOct",
    "ice_volume_flux_current", "ice_volume_flux_lag1",
    "ice_volume_flux_lag2",    "ice_volume_flux_cumOct",
)
FEATURES_ATM       = ("qnet_wm2", "u10_ms", "v10_ms")
FEATURES_SPATIAL   = ("latitude", "longitude")
FEATURES_ALL       = (
    FEATURES_OCEAN
    + FEATURES_LOCAL_ICE
    + FEATURES_EXPORT
    + FEATURES_ATM
    + FEATURES_SPATIAL
)

_BLOCK_OF = {
    **{f: "ocean"   for f in FEATURES_OCEAN},
    **{f: "ice"     for f in FEATURES_LOCAL_ICE},
    **{f: "export"  for f in FEATURES_EXPORT},
    **{f: "atm"     for f in FEATURES_ATM},
    **{f: "spatial" for f in FEATURES_SPATIAL},
}

def block_of(feature):
    """Return the predictor-block name for a given feature, or 'other'."""
    return _BLOCK_OF.get(feature, "other")


PRETTY = {
    # Ocean
    "thetao":   "SST (potential temperature)",
    "so":       "Salinity",
    "mlotst":   "Mixed-layer depth",
    # Local ice
    "siconc":       "Sea-ice concentration",
    "sithick":      "Sea-ice thickness",
    "siconc_lag1":  "Sea-ice concentration (lag-1)",
    "sithick_lag1": "Sea-ice thickness (lag-1)",
    # Export — area
    "ice_area_flux_current": "Ice area flux — current",
    "ice_area_flux_lag1":    "Ice area flux — lag-1",
    "ice_area_flux_lag2":    "Ice area flux — lag-2",
    "ice_area_flux_cumOct":  "Ice area flux — cum. Oct",
    # Export — volume
    "ice_volume_flux_current": "Ice volume flux — current",
    "ice_volume_flux_lag1":    "Ice volume flux — lag-1",
    "ice_volume_flux_lag2":    "Ice volume flux — lag-2",
    "ice_volume_flux_cumOct":  "Ice volume flux — cum. Oct",
    # Atmospheric
    "qnet_wm2": "Net surface heat flux\n(positive = ocean loss)",
    "u10_ms":   "10 m zonal wind",
    "v10_ms":   "10 m meridional wind",
    # Spatial
    "latitude":  "Latitude",
    "longitude": "Longitude",
}

short_label = {
    "thetao":"SST","so":"SAL","mlotst":"MLD",
    "siconc":"SIC","sithick":"SIT","siconc_lag1":"SIC-1","sithick_lag1":"SIT-1",
    "ice_area_flux_current":"AF-cur","ice_area_flux_lag1":"AF-1",
    "ice_area_flux_lag2":"AF-2","ice_area_flux_cumOct":"AF-cum",
    "ice_volume_flux_current":"VF-cur","ice_volume_flux_lag1":"VF-1",
    "ice_volume_flux_lag2":"VF-2","ice_volume_flux_cumOct":"VF-cum",
    "qnet_wm2":"Qnet","u10_ms":"U10","v10_ms":"V10",
    "latitude":"LAT","longitude":"LON",
    "class_fraction__phaeocystis":"Phaeo",
    "class_fraction__diatoms":"Diat",
    "class_fraction__coccolithophores":"Cocco",
}
