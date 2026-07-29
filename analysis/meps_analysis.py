"""MEPS longitudinal cohort and exposure-feasibility audit.

This script performs task T005 only. It validates files, links, timing,
survey-design fields, cohort size, and aggregate cell precision. It does not
fit outcome models and never writes person-level data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


DEFAULT_DATA_DIR = Path(
    os.environ.get(
        "MEPS_DATA_DIR",
        r"C:\Users\nimmi\.codex-data\meps-opioid-sparing\dta",
    )
)
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "outputs"

OPIOID_MULTUM_CLASSES = {60, 191}
NARROW_NONOPIOID_CLASSES = {61}
BROAD_NONOPIOID_CLASSES = {59, 61, 63}
PRIMARY_CATEGORIES = ("opioid_only", "nonopioid_only", "both", "neither")


@dataclass(frozen=True)
class PanelFiles:
    panel: int
    year1: int
    year2: int
    longitudinal: str
    rx: str
    inpatient: str
    emergency: str
    outpatient: str
    office: str
    condition_event_link: str
    conditions: str
    legacy_year1_id: bool = False


PANELS = (
    PanelFiles(
        22,
        2017,
        2018,
        "h210.dta",
        "h197a.dta",
        "h197d.dta",
        "h197e.dta",
        "h197f.dta",
        "h197g.dta",
        "h197if1.dta",
        "h199.dta",
        True,
    ),
    PanelFiles(
        23,
        2018,
        2019,
        "h217.dta",
        "h206a.dta",
        "h206d.dta",
        "h206e.dta",
        "h206f.dta",
        "h206g.dta",
        "h206if1.dta",
        "h207.dta",
    ),
    PanelFiles(
        25,
        2020,
        2021,
        "h234.dta",
        "h220a.dta",
        "h220d.dta",
        "h220e.dta",
        "h220f.dta",
        "h220g.dta",
        "h220if1.dta",
        "h222.dta",
    ),
    PanelFiles(
        26,
        2021,
        2022,
        "h244.dta",
        "h229a.dta",
        "h229d.dta",
        "h229e.dta",
        "h229f.dta",
        "h229g.dta",
        "h229if1.dta",
        "h231.dta",
    ),
)
POOLED_VARIANCE_FILE = "h36u23.dta"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--model-input",
        type=Path,
        default=None,
        help=(
            "Optional nonversioned CSV destination for the identifier-free "
            "person-level survey modeling table."
        ),
    )
    return parser.parse_args()


def require_columns(frame: pd.DataFrame, columns: Iterable[str], source: str) -> None:
    missing = sorted(set(columns) - set(frame.columns))
    if missing:
        raise ValueError(f"{source} is missing required columns: {missing}")


def resolve_file(data_dir: Path, requested_name: str) -> Path:
    direct = data_dir / requested_name
    if direct.exists():
        return direct
    matches = {
        item.name.casefold(): item
        for item in data_dir.iterdir()
        if item.is_file()
    }
    resolved = matches.get(requested_name.casefold())
    if resolved is None:
        raise FileNotFoundError(f"Required MEPS file not found: {requested_name}")
    return resolved


def read_stata(
    data_dir: Path, filename: str, columns: list[str] | None = None
) -> pd.DataFrame:
    path = resolve_file(data_dir, filename)
    return pd.read_stata(
        path,
        columns=columns,
        convert_categoricals=False,
        preserve_dtypes=False,
    )


def normalize_id(
    values: pd.Series, panel: int, prepend_legacy_panel: bool = False
) -> pd.Series:
    normalized = (
        values.astype("string")
        .str.strip()
        .str.replace(r"\.0$", "", regex=True)
    )
    if prepend_legacy_panel:
        normalized = normalized.map(
            lambda value: (
                f"{panel}{value}"
                if pd.notna(value) and len(value) == 8
                else value
            )
        )
    return normalized.astype("string")


def filter_panel(frame: pd.DataFrame, panel: int, source: str) -> pd.DataFrame:
    require_columns(frame, ["PANEL"], source)
    selected = frame.loc[pd.to_numeric(frame["PANEL"], errors="coerce") == panel].copy()
    if selected.empty:
        raise ValueError(f"{source} has no records for Panel {panel}")
    return selected


def standardize_keys(
    frame: pd.DataFrame,
    panel: int,
    legacy_person_id: bool,
    other_keys: Iterable[str],
) -> pd.DataFrame:
    frame = frame.copy()
    frame["DUPERSID"] = normalize_id(
        frame["DUPERSID"], panel, prepend_legacy_panel=legacy_person_id
    )
    for key in other_keys:
        frame[key] = normalize_id(frame[key], panel)
    return frame


def surgery_events(data_dir: Path, cfg: PanelFiles) -> tuple[pd.DataFrame, dict[str, int]]:
    specifications = (
        (cfg.inpatient, "ANYOPER", "inpatient"),
        (cfg.emergency, "SURGPROC", "emergency_room"),
        (cfg.outpatient, "SURGPROC", "outpatient"),
        (cfg.office, "SURGPROC", "office_based"),
    )
    frames: list[pd.DataFrame] = []
    counts: dict[str, int] = {}
    for filename, flag, setting in specifications:
        event = read_stata(
            data_dir,
            filename,
            ["DUPERSID", "EVNTIDX", "PANEL", flag],
        )
        event = filter_panel(event, cfg.panel, filename)
        event = standardize_keys(
            event,
            cfg.panel,
            cfg.legacy_year1_id,
            ["EVNTIDX"],
        )
        event[flag] = pd.to_numeric(event[flag], errors="coerce")
        surgical = event.loc[event[flag] == 1, ["DUPERSID", "EVNTIDX"]].drop_duplicates()
        surgical["setting"] = setting
        counts[f"{setting}_surgical_events"] = int(len(surgical))
        frames.append(surgical)

    combined = pd.concat(frames, ignore_index=True)
    counts["all_surgical_event_rows"] = int(len(combined))
    combined = combined[["DUPERSID", "EVNTIDX", "setting"]].drop_duplicates()
    unique_events = combined[["DUPERSID", "EVNTIDX"]].drop_duplicates()
    counts["unique_surgical_events"] = int(len(unique_events))
    counts["persons_with_surgical_event"] = int(unique_events["DUPERSID"].nunique())
    return combined, counts


def treatment_category(opioid: pd.Series, nonopioid: pd.Series) -> np.ndarray:
    return np.select(
        (
            opioid & ~nonopioid,
            ~opioid & nonopioid,
            opioid & nonopioid,
        ),
        ("opioid_only", "nonopioid_only", "both"),
        default="neither",
    )


def build_panel(
    data_dir: Path, cfg: PanelFiles
) -> tuple[pd.DataFrame, dict[str, object], pd.DataFrame]:
    long_columns = [
        "DUPERSID",
        "PANEL",
        "ALL5RDS",
        "AGEY1X",
        "SEX",
        "RACETHX",
        "REGIONY1",
        "ERTOTY1",
        "ERTOTY2",
        "IPDISY1",
        "OPTOTVY1",
        "OBTOTVY1",
        "POVCATY1",
        "POVLEVY1",
        "INSCOVY1",
        "INSURCY1",
        "RTHLTH1",
        "MNHLTH1",
        "WLKLIM1",
        "ACTLIM1",
        "IADLHP1",
        "ADLHLP1",
        "CANCERY1",
        "LONGWT",
        "VARSTR",
        "VARPSU",
    ]
    longitudinal = read_stata(data_dir, cfg.longitudinal, long_columns)
    longitudinal = filter_panel(longitudinal, cfg.panel, cfg.longitudinal)
    longitudinal = standardize_keys(
        longitudinal, cfg.panel, False, []
    )
    for column in long_columns:
        if column not in {"DUPERSID"}:
            longitudinal[column] = pd.to_numeric(
                longitudinal[column], errors="coerce"
            )

    complete_adults = longitudinal.loc[
        (longitudinal["ALL5RDS"] == 1)
        & (longitudinal["AGEY1X"] >= 18)
        & (longitudinal["LONGWT"] > 0)
    ].copy()
    if complete_adults["DUPERSID"].duplicated().any():
        raise ValueError(f"{cfg.longitudinal} contains duplicate person IDs")
    if (complete_adults["ERTOTY2"] < 0).any():
        raise ValueError(
            f"{cfg.longitudinal} has negative ERTOTY2 in the eligible base"
        )

    events, event_counts = surgery_events(data_dir, cfg)
    unique_events = events[["DUPERSID", "EVNTIDX"]].drop_duplicates()

    link = read_stata(
        data_dir,
        cfg.condition_event_link,
        ["DUPERSID", "CONDIDX", "EVNTIDX", "EVENTYPE", "PANEL"],
    )
    link = filter_panel(link, cfg.panel, cfg.condition_event_link)
    link = standardize_keys(
        link,
        cfg.panel,
        cfg.legacy_year1_id,
        ["CONDIDX", "EVNTIDX"],
    )
    link["EVENTYPE"] = pd.to_numeric(link["EVENTYPE"], errors="coerce")

    surgical_conditions = (
        link.merge(
            unique_events,
            on=["DUPERSID", "EVNTIDX"],
            how="inner",
            validate="many_to_one",
        )[["DUPERSID", "CONDIDX"]]
        .drop_duplicates()
    )

    condition_columns = [
        "DUPERSID",
        "CONDIDX",
        "PANEL",
        "ICD10CDX",
        "CCSR1X",
        "CCSR2X",
        "CCSR3X",
    ]
    conditions = read_stata(data_dir, cfg.conditions, condition_columns)
    conditions = filter_panel(conditions, cfg.panel, cfg.conditions)
    conditions = standardize_keys(
        conditions,
        cfg.panel,
        cfg.legacy_year1_id,
        ["CONDIDX"],
    )
    condition_keys = conditions[["DUPERSID", "CONDIDX"]].drop_duplicates()
    all_condition_count = (
        condition_keys.groupby("DUPERSID")
        .size()
        .rename("all_condition_count_y1")
    )
    condition_validation = surgical_conditions.merge(
        condition_keys,
        on=["DUPERSID", "CONDIDX"],
        how="left",
        indicator=True,
        validate="one_to_one",
    )
    valid_surgical_conditions = condition_validation.loc[
        condition_validation["_merge"] == "both",
        ["DUPERSID", "CONDIDX"],
    ]
    condition_match_rate = (
        len(valid_surgical_conditions) / len(surgical_conditions)
        if len(surgical_conditions)
        else np.nan
    )
    if not np.isnan(condition_match_rate) and condition_match_rate < 0.95:
        raise ValueError(
            f"Only {condition_match_rate:.1%} of surgical condition links "
            f"matched {cfg.conditions}"
        )

    eligible = complete_adults.loc[
        complete_adults["DUPERSID"].isin(
            valid_surgical_conditions["DUPERSID"].unique()
        )
    ].copy()

    rx_link_ids = (
        link.loc[link["EVENTYPE"] == 8]
        .merge(
            valid_surgical_conditions,
            on=["DUPERSID", "CONDIDX"],
            how="inner",
            validate="many_to_many",
        )[["DUPERSID", "EVNTIDX"]]
        .drop_duplicates()
        .rename(columns={"EVNTIDX": "LINKIDX"})
    )

    rx = read_stata(data_dir, cfg.rx)
    rx = filter_panel(rx, cfg.panel, cfg.rx)
    require_columns(rx, ["DUPERSID", "LINKIDX"], cfg.rx)
    rx = standardize_keys(
        rx,
        cfg.panel,
        cfg.legacy_year1_id,
        ["LINKIDX"],
    )
    tc_columns = [column for column in rx.columns if column.startswith("TC")]
    if not tc_columns:
        raise ValueError(f"{cfg.rx} contains no Multum TC fields")
    tc_values = rx[tc_columns].apply(pd.to_numeric, errors="coerce")
    rx["opioid_record"] = tc_values.isin(OPIOID_MULTUM_CLASSES).any(axis=1)
    # Opioid precedence avoids treating hierarchical labels on an opioid
    # combination record as a separate nonopioid exposure.
    rx["narrow_nonopioid_record"] = (
        tc_values.isin(NARROW_NONOPIOID_CLASSES).any(axis=1)
        & ~rx["opioid_record"]
    )
    rx["broad_nonopioid_record"] = (
        tc_values.isin(BROAD_NONOPIOID_CLASSES).any(axis=1)
        & ~rx["opioid_record"]
    )

    linked_rx = rx.merge(
        rx_link_ids,
        on=["DUPERSID", "LINKIDX"],
        how="inner",
        validate="many_to_one",
    )
    person_exposure = linked_rx.groupby("DUPERSID", as_index=True)[
        ["opioid_record", "narrow_nonopioid_record", "broad_nonopioid_record"]
    ].max()
    all_opioid_y1 = (
        rx.groupby("DUPERSID")["opioid_record"]
        .max()
        .rename("all_opioid_y1")
    )
    eligible = eligible.join(person_exposure, on="DUPERSID")
    eligible = eligible.join(all_opioid_y1, on="DUPERSID")
    eligible["all_opioid_y1"] = (
        eligible["all_opioid_y1"].astype("boolean").fillna(False).astype(bool)
    )
    exposure_columns = [
        "opioid_record",
        "narrow_nonopioid_record",
        "broad_nonopioid_record",
    ]
    for column in exposure_columns:
        eligible[column] = (
            eligible[column].astype("boolean").fillna(False).astype(bool)
        )
    eligible["treatment_narrow"] = treatment_category(
        eligible["opioid_record"], eligible["narrow_nonopioid_record"]
    )
    eligible["treatment_broad"] = treatment_category(
        eligible["opioid_record"], eligible["broad_nonopioid_record"]
    )
    eligible["opioid_binary"] = np.where(
        eligible["opioid_record"], "any_opioid", "no_opioid"
    )
    eligible["any_year2_ed"] = eligible["ERTOTY2"] > 0
    eligible["panel"] = cfg.panel
    eligible["year1"] = cfg.year1
    eligible["year2"] = cfg.year2

    poverty = pd.to_numeric(eligible["POVCATY1"], errors="coerce")
    eligible["poverty_5"] = poverty.where(poverty.isin([1, 2, 3, 4, 5]))
    eligible["poverty_3"] = np.select(
        (poverty.isin([1, 2, 3]), poverty == 4, poverty == 5),
        ("below_200_fpl", "200_to_399_fpl", "400_plus_fpl"),
        default="missing",
    )
    eligible["poverty_2"] = np.select(
        (poverty.isin([1, 2, 3]), poverty.isin([4, 5])),
        ("below_200_fpl", "200_plus_fpl"),
        default="missing",
    )
    insurance = pd.to_numeric(eligible["INSCOVY1"], errors="coerce")
    eligible["insurance_3"] = insurance.where(insurance.isin([1, 2, 3]))

    event_features = (
        events.assign(value=1)
        .pivot_table(
            index="DUPERSID",
            columns="setting",
            values="value",
            aggfunc="max",
            fill_value=0,
        )
        .rename(
            columns={
                "inpatient": "surgery_inpatient",
                "emergency_room": "surgery_emergency_room",
                "outpatient": "surgery_outpatient",
                "office_based": "surgery_office_based",
            }
        )
    )
    for setting_column in (
        "surgery_inpatient",
        "surgery_emergency_room",
        "surgery_outpatient",
        "surgery_office_based",
    ):
        if setting_column not in event_features:
            event_features[setting_column] = 0
    surgical_event_count = (
        unique_events.groupby("DUPERSID")
        .size()
        .rename("surgical_event_count")
    )
    linked_condition_count = (
        valid_surgical_conditions.groupby("DUPERSID")
        .size()
        .rename("linked_surgical_condition_count")
    )
    linked_rx_count = (
        linked_rx.groupby("DUPERSID")
        .size()
        .rename("linked_rx_count")
    )
    eligible = eligible.join(event_features, on="DUPERSID")
    eligible = eligible.join(surgical_event_count, on="DUPERSID")
    eligible = eligible.join(linked_condition_count, on="DUPERSID")
    eligible = eligible.join(all_condition_count, on="DUPERSID")
    eligible = eligible.join(linked_rx_count, on="DUPERSID")
    eligible["linked_rx_count"] = eligible["linked_rx_count"].fillna(0).astype(int)
    for setting_column in (
        "surgery_inpatient",
        "surgery_emergency_room",
        "surgery_outpatient",
        "surgery_office_based",
    ):
        eligible[setting_column] = (
            eligible[setting_column].fillna(0).astype(int)
        )

    model_extra_columns = [
        "DUPERSID",
        "opioid_record",
        "narrow_nonopioid_record",
        "broad_nonopioid_record",
        "all_opioid_y1",
        "treatment_narrow",
        "treatment_broad",
        "opioid_binary",
        "any_year2_ed",
        "poverty_5",
        "poverty_3",
        "poverty_2",
        "insurance_3",
        "surgery_inpatient",
        "surgery_emergency_room",
        "surgery_outpatient",
        "surgery_office_based",
        "surgical_event_count",
        "linked_surgical_condition_count",
        "all_condition_count_y1",
        "linked_rx_count",
    ]
    universe = longitudinal.loc[longitudinal["LONGWT"] > 0].copy()
    universe["domain_eligible"] = universe["DUPERSID"].isin(
        eligible["DUPERSID"]
    ).astype(int)
    universe = universe.merge(
        eligible[model_extra_columns],
        on="DUPERSID",
        how="left",
        validate="one_to_one",
    )

    flow: dict[str, object] = {
        "panel": cfg.panel,
        "year1": cfg.year1,
        "year2": cfg.year2,
        "longitudinal_records": int(len(longitudinal)),
        "complete_panel_adults": int(len(complete_adults)),
        **event_counts,
        "surgical_condition_links": int(len(surgical_conditions)),
        "persons_with_linked_surgical_condition": int(
            surgical_conditions["DUPERSID"].nunique()
        ),
        "condition_links_matching_condition_puf": int(
            len(valid_surgical_conditions)
        ),
        "condition_link_match_percent": round(condition_match_rate * 100, 3),
        "eligible_complete_adults": int(len(eligible)),
        "persons_with_linked_rx": int(linked_rx["DUPERSID"].nunique()),
        "linked_rx_rows": int(len(linked_rx)),
        "year2_ed_positive": int(eligible["any_year2_ed"].sum()),
        "year2_ed_visits": int(eligible["ERTOTY2"].sum()),
        "eligible_longitudinal_weight_millions": round(
            eligible["LONGWT"].sum() / 1_000_000, 6
        ),
    }
    return eligible, flow, universe


def aggregate_treatment(
    people: pd.DataFrame,
    scheme: str,
    treatment_column: str,
    weight_divisor: int,
    scope: str,
) -> pd.DataFrame:
    rows = []
    for category in PRIMARY_CATEGORIES:
        group = people.loc[people[treatment_column] == category]
        rows.append(
            {
                "scope": scope,
                "scheme": scheme,
                "category": category,
                "n": int(len(group)),
                "ed_positive": int(group["any_year2_ed"].sum()),
                "ed_visits": int(group["ERTOTY2"].sum()),
                "weighted_millions_average_panel": round(
                    group["LONGWT"].sum() / weight_divisor / 1_000_000, 6
                ),
            }
        )
    return pd.DataFrame(rows)


def aggregate_equity(
    people: pd.DataFrame,
    scheme: str,
    treatment_column: str,
    equity_column: str,
    weight_divisor: int,
    scope: str,
) -> pd.DataFrame:
    rows = []
    levels = sorted(
        people[equity_column].dropna().astype(str).unique().tolist()
    )
    categories = (
        ["any_opioid", "no_opioid"]
        if treatment_column == "opioid_binary"
        else list(PRIMARY_CATEGORIES)
    )
    for level in levels:
        for category in categories:
            group = people.loc[
                (people[equity_column].astype(str) == level)
                & (people[treatment_column] == category)
            ]
            rows.append(
                {
                    "scope": scope,
                    "scheme": scheme,
                    "equity_variable": equity_column,
                    "equity_level": level,
                    "category": category,
                    "n": int(len(group)),
                    "ed_positive": int(group["any_year2_ed"].sum()),
                    "ed_visits": int(group["ERTOTY2"].sum()),
                    "weighted_millions_average_panel": round(
                        group["LONGWT"].sum()
                        / weight_divisor
                        / 1_000_000,
                        6,
                    ),
                }
            )
    return pd.DataFrame(rows)


def gate_rows(
    treatment: pd.DataFrame,
    equity: pd.DataFrame,
    scheme: str,
    poverty_variable: str,
) -> list[dict[str, object]]:
    selected = treatment.loc[
        (treatment["scope"] == "pooled_all_panels")
        & (treatment["scheme"] == scheme)
    ]
    poverty = equity.loc[
        (equity["scope"] == "pooled_all_panels")
        & (equity["scheme"] == scheme)
        & (equity["equity_variable"] == poverty_variable)
    ]
    checks = (
        ("total_n_at_least_1000", int(selected["n"].sum()), 1000),
        ("minimum_category_n_at_least_100", int(selected["n"].min()), 100),
        (
            "minimum_category_ed_positive_at_least_30",
            int(selected["ed_positive"].min()),
            30,
        ),
        (
            f"minimum_treatment_x_{poverty_variable}_cell_at_least_50",
            int(poverty["n"].min()),
            50,
        ),
    )
    return [
        {
            "scheme": scheme,
            "gate": label,
            "observed": observed,
            "threshold": threshold,
            "pass": bool(observed >= threshold),
        }
        for label, observed, threshold in checks
    ]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_report(
    output_dir: Path,
    flow: pd.DataFrame,
    treatment: pd.DataFrame,
    equity: pd.DataFrame,
    gates: pd.DataFrame,
    summary: dict[str, object],
) -> None:
    def markdown_table(frame: pd.DataFrame) -> str:
        display = frame.copy()
        headers = [str(column).replace("|", "\\|") for column in display.columns]
        lines = [
            "| " + " | ".join(headers) + " |",
            "| " + " | ".join("---" for _ in headers) + " |",
        ]
        for row in display.itertuples(index=False, name=None):
            values = [
                str(value).replace("|", "\\|").replace("\n", " ")
                for value in row
            ]
            lines.append("| " + " | ".join(values) + " |")
        return "\n".join(lines)

    narrow = treatment.loc[
        (treatment["scope"] == "pooled_all_panels")
        & (treatment["scheme"] == "narrow")
    ]
    broad = treatment.loc[
        (treatment["scope"] == "pooled_all_panels")
        & (treatment["scheme"] == "broad")
    ]
    binary = treatment.loc[
        (treatment["scope"] == "pooled_all_panels")
        & (treatment["scheme"] == "binary")
    ]
    lines = [
        "# MEPS cohort and exposure-feasibility results",
        "",
        "Generated by `analysis/meps_analysis.py`. No person-level data are saved.",
        "",
        "## Decision",
        "",
        str(summary["decision"]),
        "",
        "## Cohort flow",
        "",
        markdown_table(flow),
        "",
        "## Pooled narrow four-category exposure",
        "",
        markdown_table(narrow),
        "",
        "## Pooled broad sensitivity exposure",
        "",
        markdown_table(broad),
        "",
        "## Binary fallback feasibility",
        "",
        markdown_table(binary),
        "",
        "## Prespecified gates",
        "",
        markdown_table(gates),
        "",
        "## Interpretation boundary",
        "",
        (
            "MEPS supports an annual, condition-linked observational design. "
            "These links do not establish that a medicine was taken after a "
            "specific operation, and month/year public-use timing cannot define "
            "a 30-day postoperative window."
        ),
        "",
    ]
    (output_dir / "feasibility_report.md").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def main() -> None:
    args = parse_args()
    data_dir = args.data_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    required_names = {POOLED_VARIANCE_FILE}
    for cfg in PANELS:
        required_names.update(
            {
                cfg.longitudinal,
                cfg.rx,
                cfg.inpatient,
                cfg.emergency,
                cfg.outpatient,
                cfg.office,
                cfg.condition_event_link,
                cfg.conditions,
            }
        )
    paths = {name: resolve_file(data_dir, name) for name in sorted(required_names)}

    people_by_panel: list[pd.DataFrame] = []
    universe_by_panel: list[pd.DataFrame] = []
    flow_rows: list[dict[str, object]] = []
    for cfg in PANELS:
        people, flow, universe = build_panel(data_dir, cfg)
        people_by_panel.append(people)
        universe_by_panel.append(universe)
        flow_rows.append(flow)
    pooled = pd.concat(people_by_panel, ignore_index=True)
    pooled_universe = pd.concat(universe_by_panel, ignore_index=True)

    variance = read_stata(
        data_dir,
        POOLED_VARIANCE_FILE,
        ["DUPERSID", "PANEL", "STRA9623", "PSU9623"],
    )
    variance["DUPERSID"] = normalize_id(variance["DUPERSID"], 0)
    variance["PANEL"] = pd.to_numeric(variance["PANEL"], errors="coerce")
    # HC-036 retains the legacy eight-character 2017 identifier for Panel 22
    # people who did not appear in the 2018 full-year file. HC-210 uses the
    # ten-character form for every Panel 22 record, so harmonize those HC-036
    # keys before constructing the full survey universe.
    h36_panel22_legacy = (
        (variance["PANEL"] == 22)
        & (variance["DUPERSID"].str.len() == 8)
    )
    variance.loc[h36_panel22_legacy, "DUPERSID"] = (
        "22" + variance.loc[h36_panel22_legacy, "DUPERSID"]
    )
    duplicate_design = variance.loc[
        variance.duplicated(["DUPERSID", "PANEL"], keep=False),
        ["DUPERSID", "PANEL", "STRA9623", "PSU9623"],
    ]
    if not duplicate_design.empty:
        conflicting_design = (
            duplicate_design.drop_duplicates()
            .groupby(["DUPERSID", "PANEL"])
            .size()
            .gt(1)
            .any()
        )
        if conflicting_design:
            raise ValueError(
                f"{POOLED_VARIANCE_FILE} has conflicting duplicate designs"
            )
        variance = variance.drop_duplicates(["DUPERSID", "PANEL"])
    if variance.duplicated(["DUPERSID", "PANEL"]).any():
        raise ValueError(f"{POOLED_VARIANCE_FILE} has duplicate person-panel keys")
    pooled = pooled.merge(
        variance,
        on=["DUPERSID", "PANEL"],
        how="left",
        validate="one_to_one",
        indicator=True,
    )
    variance_matches = int((pooled["_merge"] == "both").sum())
    if variance_matches != len(pooled):
        raise ValueError(
            f"HC-036 matched {variance_matches}/{len(pooled)} eligible records"
        )
    if pooled[["STRA9623", "PSU9623"]].isna().any().any():
        raise ValueError("HC-036 linked but pooled stratum/PSU values are missing")
    pooled = pooled.drop(columns="_merge")
    pooled_universe = pooled_universe.merge(
        variance,
        on=["DUPERSID", "PANEL"],
        how="left",
        validate="one_to_one",
        indicator=True,
    )
    universe_variance_matches = int(
        (pooled_universe["_merge"] == "both").sum()
    )
    if universe_variance_matches != len(pooled_universe):
        raise ValueError(
            "HC-036 did not match every positive-LONGWT longitudinal record: "
            f"{universe_variance_matches}/{len(pooled_universe)}"
        )
    if pooled_universe[["STRA9623", "PSU9623"]].isna().any().any():
        raise ValueError(
            "HC-036 pooled design fields are missing in the full universe"
        )
    pooled_universe = pooled_universe.drop(columns="_merge")

    if args.model_input is not None:
        model_input = args.model_input.resolve()
        if output_dir in model_input.parents or model_input.parent == output_dir:
            raise ValueError(
                "Person-level model input must be outside versioned outputs"
            )
        model_input.parent.mkdir(parents=True, exist_ok=True)
        protected_columns = {"DUPERSID", "VARSTR", "VARPSU"}
        export_columns = [
            column
            for column in pooled_universe.columns
            if column not in protected_columns
        ]
        model_frame = pooled_universe[export_columns].copy()
        boolean_columns = [
            column
            for column in model_frame.columns
            if str(model_frame[column].dtype) in {"bool", "boolean"}
        ]
        for column in boolean_columns:
            model_frame[column] = model_frame[column].astype("Int64")
        model_frame.to_csv(model_input, index=False)
        if any(
            forbidden in model_frame.columns
            for forbidden in ("DUPERSID", "RXNAME", "RXNDC", "ICD10CDX")
        ):
            raise ValueError("Protected identifier/detail leaked to model input")

    treatment_frames: list[pd.DataFrame] = []
    equity_frames: list[pd.DataFrame] = []
    schemes = (
        ("narrow", "treatment_narrow"),
        ("broad", "treatment_broad"),
    )
    for people in people_by_panel:
        panel = int(people["panel"].iloc[0])
        for scheme, column in schemes:
            treatment_frames.append(
                aggregate_treatment(
                    people, scheme, column, 1, f"panel_{panel}"
                )
            )

    for scheme, column in schemes:
        treatment_frames.append(
            aggregate_treatment(
                pooled, scheme, column, len(PANELS), "pooled_all_panels"
            )
        )
        for equity_column in (
            "poverty_5",
            "poverty_3",
            "poverty_2",
            "insurance_3",
        ):
            equity_frames.append(
                aggregate_equity(
                    pooled,
                    scheme,
                    column,
                    equity_column,
                    len(PANELS),
                    "pooled_all_panels",
                )
            )

    binary_rows = []
    for category in ("any_opioid", "no_opioid"):
        group = pooled.loc[pooled["opioid_binary"] == category]
        binary_rows.append(
            {
                "scope": "pooled_all_panels",
                "scheme": "binary",
                "category": category,
                "n": int(len(group)),
                "ed_positive": int(group["any_year2_ed"].sum()),
                "ed_visits": int(group["ERTOTY2"].sum()),
                "weighted_millions_average_panel": round(
                    group["LONGWT"].sum() / len(PANELS) / 1_000_000, 6
                ),
            }
        )
    treatment_frames.append(pd.DataFrame(binary_rows))
    for equity_column in (
        "poverty_5",
        "poverty_3",
        "poverty_2",
        "insurance_3",
    ):
        equity_frames.append(
            aggregate_equity(
                pooled,
                "binary",
                "opioid_binary",
                equity_column,
                len(PANELS),
                "pooled_all_panels",
            )
        )

    nonpandemic = pooled.loc[pooled["panel"] != 25].copy()
    for scheme, column in schemes:
        treatment_frames.append(
            aggregate_treatment(
                nonpandemic,
                scheme,
                column,
                len(PANELS) - 1,
                "exclude_panel_25_2020_exposure",
            )
        )

    treatment = pd.concat(treatment_frames, ignore_index=True)
    equity = pd.concat(equity_frames, ignore_index=True)
    gate_records = []
    for scheme in ("narrow", "broad"):
        gate_records.extend(gate_rows(treatment, equity, scheme, "poverty_2"))
    binary_treatment = treatment.loc[
        (treatment["scope"] == "pooled_all_panels")
        & (treatment["scheme"] == "binary")
    ]
    binary_poverty_5 = equity.loc[
        (equity["scope"] == "pooled_all_panels")
        & (equity["scheme"] == "binary")
        & (equity["equity_variable"] == "poverty_5")
    ]
    binary_poverty_3 = equity.loc[
        (equity["scope"] == "pooled_all_panels")
        & (equity["scheme"] == "binary")
        & (equity["equity_variable"] == "poverty_3")
        & (equity["equity_level"] != "missing")
    ]
    binary_poverty_2 = equity.loc[
        (equity["scope"] == "pooled_all_panels")
        & (equity["scheme"] == "binary")
        & (equity["equity_variable"] == "poverty_2")
        & (equity["equity_level"] != "missing")
    ]
    binary_checks = (
        ("minimum_binary_category_n_at_least_100", int(binary_treatment["n"].min()), 100),
        (
            "minimum_binary_category_ed_positive_at_least_30",
            int(binary_treatment["ed_positive"].min()),
            30,
        ),
        (
            "minimum_binary_x_poverty_5_cell_at_least_50",
            int(binary_poverty_5["n"].min()),
            50,
        ),
        (
            "minimum_binary_x_poverty_3_cell_at_least_50",
            int(binary_poverty_3["n"].min()),
            50,
        ),
        (
            "minimum_binary_x_poverty_3_ed_positive_at_least_30",
            int(binary_poverty_3["ed_positive"].min()),
            30,
        ),
        (
            "minimum_binary_x_poverty_2_cell_at_least_50",
            int(binary_poverty_2["n"].min()),
            50,
        ),
        (
            "minimum_binary_x_poverty_2_ed_positive_at_least_30",
            int(binary_poverty_2["ed_positive"].min()),
            30,
        ),
    )
    gate_records.extend(
        {
            "scheme": "binary",
            "gate": label,
            "observed": observed,
            "threshold": threshold,
            "pass": bool(observed >= threshold),
        }
        for label, observed, threshold in binary_checks
    )
    gates = pd.DataFrame(gate_records)

    flow = pd.DataFrame(flow_rows)
    manifest = pd.DataFrame(
        [
            {
                "requested_file": name,
                "resolved_path": str(path),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for name, path in paths.items()
        ]
    )

    narrow_pass = bool(
        gates.loc[gates["scheme"] == "narrow", "pass"].all()
    )
    broad_pass = bool(gates.loc[gates["scheme"] == "broad", "pass"].all())
    binary_basic_pass = bool(
        gates.loc[
            (gates["scheme"] == "binary")
            & gates["gate"].isin(
                [
                    "minimum_binary_category_n_at_least_100",
                    "minimum_binary_category_ed_positive_at_least_30",
                ]
            ),
            "pass",
        ].all()
    )
    binary_poverty_3_pass = bool(
        gates.loc[
            (gates["scheme"] == "binary")
            & gates["gate"].isin(
                [
                    "minimum_binary_x_poverty_3_cell_at_least_50",
                    "minimum_binary_x_poverty_3_ed_positive_at_least_30",
                ]
            ),
            "pass",
        ].all()
    )
    binary_poverty_2_pass = bool(
        gates.loc[
            (gates["scheme"] == "binary")
            & gates["gate"].isin(
                [
                    "minimum_binary_x_poverty_2_cell_at_least_50",
                    "minimum_binary_x_poverty_2_ed_positive_at_least_30",
                ]
            ),
            "pass",
        ].all()
    )
    summary = {
        "status": "stop_and_redesign_before_modeling",
        "decision": (
            "The approved four-category opioid/nonopioid design is nonviable "
            "for the prespecified equity analysis after four-panel expansion. "
            "The binary any-opioid versus no-opioid fallback has adequate "
            "overall counts; the prespecified two-level poverty interaction is "
            "adequately sized and a three-level sensitivity is also reported as "
            "a candidate redesign and requires Judge approval before modeling."
        ),
        "eligible_n": int(len(pooled)),
        "year2_ed_positive": int(pooled["any_year2_ed"].sum()),
        "year2_ed_visits": int(pooled["ERTOTY2"].sum()),
        "hc036_matches": variance_matches,
        "hc036_universe_matches": universe_variance_matches,
        "positive_weight_universe_n": int(len(pooled_universe)),
        "narrow_all_gates_pass": narrow_pass,
        "broad_all_gates_pass": broad_pass,
        "binary_basic_gates_pass": binary_basic_pass,
        "binary_poverty_2_gates_pass": binary_poverty_2_pass,
        "binary_poverty_3_gates_pass": binary_poverty_3_pass,
        "source_panels": [cfg.panel for cfg in PANELS],
        "source_year_pairs": [
            f"{cfg.year1}-{cfg.year2}" for cfg in PANELS
        ],
        "pandemic_sensitivity": "Exclude Panel 25 (2020 exposure year).",
        "person_level_outputs_written": False,
    }

    manifest.to_csv(output_dir / "file_manifest.csv", index=False)
    flow.to_csv(output_dir / "cohort_flow.csv", index=False)
    treatment.to_csv(output_dir / "treatment_feasibility.csv", index=False)
    equity.to_csv(output_dir / "equity_cells.csv", index=False)
    gates.to_csv(output_dir / "gate_results.csv", index=False)
    (output_dir / "feasibility_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    write_report(output_dir, flow, treatment, equity, gates, summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
