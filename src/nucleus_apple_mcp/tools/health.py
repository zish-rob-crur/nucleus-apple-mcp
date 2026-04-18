from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import json
import math
import os
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from pathlib import Path
from statistics import StatisticsError, mean, median, quantiles
from typing import Annotated, Any, Literal, Protocol
from urllib.parse import quote, urlparse

import httpx
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field, ValidationError

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

health_router = FastMCP(name="health")

_StorageBackendName = Literal["auto", "s3_object_store"]


class HealthSampleKind(str, Enum):
    quantity = "quantity"
    category = "category"
    workout = "workout"
    correlation = "correlation"


class HealthSampleTag(str, Enum):
    activity = "activity"
    cardio = "cardio"
    sleep = "sleep"
    body = "body"
    metabolic = "metabolic"


@dataclass(frozen=True)
class _SampleTypeCatalogEntry:
    type_key: str
    kind: HealthSampleKind
    tags: tuple[HealthSampleTag, ...]
    description: str
    unit: str | None = None
    related_metric_keys: tuple[str, ...] = ()
    aggregate_hint: str | None = None


@dataclass(frozen=True)
class _MetricSourceCatalogEntry:
    metric_key: str
    source_model: str
    related_type_keys: tuple[str, ...]
    aggregate_hint: str
    description: str


_SAMPLE_CATALOG: tuple[_SampleTypeCatalogEntry, ...] = (
    _SampleTypeCatalogEntry(
        type_key="step_count",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.activity,),
        description="Incremental step count samples.",
        unit="count",
        related_metric_keys=("steps",),
        aggregate_hint="sum_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="active_energy_burned",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.activity,),
        description="Active energy burn samples.",
        unit="kcal",
        related_metric_keys=("active_energy_kcal",),
        aggregate_hint="activity_summary_context",
    ),
    _SampleTypeCatalogEntry(
        type_key="heart_rate",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.cardio,),
        description="Heart rate samples.",
        unit="bpm",
    ),
    _SampleTypeCatalogEntry(
        type_key="resting_heart_rate",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.cardio,),
        description="Resting heart rate samples.",
        unit="bpm",
        related_metric_keys=("resting_hr_avg",),
        aggregate_hint="average_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="hrv_sdnn",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.cardio,),
        description="Heart-rate variability SDNN samples.",
        unit="ms",
        related_metric_keys=("hrv_sdnn_avg",),
        aggregate_hint="average_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="vo2_max",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.activity, HealthSampleTag.cardio),
        description="VO2 max / cardio fitness samples.",
        unit="mL/kg/min",
        related_metric_keys=("vo2_max",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="oxygen_saturation",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.cardio, HealthSampleTag.metabolic),
        description="Blood oxygen saturation samples.",
        unit="%",
        related_metric_keys=("oxygen_saturation_pct",),
        aggregate_hint="average_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="respiratory_rate",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.cardio,),
        description="Respiratory rate samples.",
        unit="brpm",
        related_metric_keys=("respiratory_rate_avg",),
        aggregate_hint="overlap_weighted_average_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="apple_sleeping_wrist_temperature",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.sleep, HealthSampleTag.body),
        description="Sleeping wrist temperature delta-from-baseline samples.",
        unit="Δ°C",
        related_metric_keys=("wrist_temperature_celsius",),
        aggregate_hint="overlap_weighted_average_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="body_mass",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.body,),
        description="Body mass / weight samples.",
        unit="kg",
        related_metric_keys=("body_mass_kg",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="body_fat_percentage",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.body,),
        description="Body fat percentage samples.",
        unit="%",
        related_metric_keys=("body_fat_percentage",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="blood_pressure",
        kind=HealthSampleKind.correlation,
        tags=(HealthSampleTag.metabolic,),
        description="Blood pressure correlation samples with systolic/diastolic components.",
        related_metric_keys=("blood_pressure_systolic_mmhg", "blood_pressure_diastolic_mmhg"),
        aggregate_hint="latest_components",
    ),
    _SampleTypeCatalogEntry(
        type_key="blood_glucose",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.metabolic,),
        description="Blood glucose samples.",
        unit="mg/dL",
        related_metric_keys=("blood_glucose_mg_dl",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="body_temperature",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.body,),
        description="Body temperature samples.",
        unit="°C",
        related_metric_keys=("body_temperature_celsius",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="basal_body_temperature",
        kind=HealthSampleKind.quantity,
        tags=(HealthSampleTag.body,),
        description="Basal body temperature samples.",
        unit="°C",
        related_metric_keys=("basal_body_temperature_celsius",),
        aggregate_hint="latest_sample",
    ),
    _SampleTypeCatalogEntry(
        type_key="sleep_analysis",
        kind=HealthSampleKind.category,
        tags=(HealthSampleTag.sleep,),
        description="Sleep stage / in-bed category samples.",
        related_metric_keys=("sleep_asleep_minutes", "sleep_in_bed_minutes"),
        aggregate_hint="category_minutes_per_day",
    ),
    _SampleTypeCatalogEntry(
        type_key="workout",
        kind=HealthSampleKind.workout,
        tags=(HealthSampleTag.activity,),
        description="Workout session records.",
        related_metric_keys=("active_energy_kcal", "exercise_minutes"),
        aggregate_hint="session_records",
    ),
)

_SAMPLE_CATALOG_BY_KEY = {entry.type_key: entry for entry in _SAMPLE_CATALOG}

_METRIC_SOURCE_CATALOG: dict[str, _MetricSourceCatalogEntry] = {
    "steps": _MetricSourceCatalogEntry(
        metric_key="steps",
        source_model="raw_aggregate",
        related_type_keys=("step_count",),
        aggregate_hint="sum_per_day",
        description="Daily sum of step count samples.",
    ),
    "active_energy_kcal": _MetricSourceCatalogEntry(
        metric_key="active_energy_kcal",
        source_model="activity_summary",
        related_type_keys=("active_energy_burned", "workout"),
        aggregate_hint="activity_summary",
        description="Derived from HKActivitySummary active energy, not directly from raw JSONL sums.",
    ),
    "exercise_minutes": _MetricSourceCatalogEntry(
        metric_key="exercise_minutes",
        source_model="activity_summary",
        related_type_keys=("workout",),
        aggregate_hint="activity_summary",
        description="Derived from HKActivitySummary exercise time.",
    ),
    "stand_hours": _MetricSourceCatalogEntry(
        metric_key="stand_hours",
        source_model="activity_summary",
        related_type_keys=(),
        aggregate_hint="activity_summary",
        description="Derived from HKActivitySummary stand hours.",
    ),
    "resting_hr_avg": _MetricSourceCatalogEntry(
        metric_key="resting_hr_avg",
        source_model="raw_aggregate",
        related_type_keys=("resting_heart_rate",),
        aggregate_hint="average_per_day",
        description="Daily average resting heart rate.",
    ),
    "hrv_sdnn_avg": _MetricSourceCatalogEntry(
        metric_key="hrv_sdnn_avg",
        source_model="raw_aggregate",
        related_type_keys=("hrv_sdnn",),
        aggregate_hint="average_per_day",
        description="Daily average HRV SDNN.",
    ),
    "vo2_max": _MetricSourceCatalogEntry(
        metric_key="vo2_max",
        source_model="raw_aggregate",
        related_type_keys=("vo2_max",),
        aggregate_hint="latest_sample",
        description="Latest VO2 max sample in the day.",
    ),
    "oxygen_saturation_pct": _MetricSourceCatalogEntry(
        metric_key="oxygen_saturation_pct",
        source_model="raw_aggregate",
        related_type_keys=("oxygen_saturation",),
        aggregate_hint="average_per_day",
        description="Daily average blood oxygen percentage.",
    ),
    "respiratory_rate_avg": _MetricSourceCatalogEntry(
        metric_key="respiratory_rate_avg",
        source_model="raw_aggregate",
        related_type_keys=("respiratory_rate",),
        aggregate_hint="overlap_weighted_average_per_day",
        description="Daily overlap-weighted average respiratory rate.",
    ),
    "wrist_temperature_celsius": _MetricSourceCatalogEntry(
        metric_key="wrist_temperature_celsius",
        source_model="raw_aggregate",
        related_type_keys=("apple_sleeping_wrist_temperature",),
        aggregate_hint="overlap_weighted_average_per_day",
        description="Daily overlap-weighted sleeping wrist temperature delta from baseline.",
    ),
    "body_mass_kg": _MetricSourceCatalogEntry(
        metric_key="body_mass_kg",
        source_model="raw_aggregate",
        related_type_keys=("body_mass",),
        aggregate_hint="latest_sample",
        description="Latest body mass sample in the day.",
    ),
    "body_fat_percentage": _MetricSourceCatalogEntry(
        metric_key="body_fat_percentage",
        source_model="raw_aggregate",
        related_type_keys=("body_fat_percentage",),
        aggregate_hint="latest_sample",
        description="Latest body fat percentage sample in the day.",
    ),
    "blood_pressure_systolic_mmhg": _MetricSourceCatalogEntry(
        metric_key="blood_pressure_systolic_mmhg",
        source_model="raw_aggregate",
        related_type_keys=("blood_pressure",),
        aggregate_hint="latest_components",
        description="Latest systolic value from blood pressure correlation samples.",
    ),
    "blood_pressure_diastolic_mmhg": _MetricSourceCatalogEntry(
        metric_key="blood_pressure_diastolic_mmhg",
        source_model="raw_aggregate",
        related_type_keys=("blood_pressure",),
        aggregate_hint="latest_components",
        description="Latest diastolic value from blood pressure correlation samples.",
    ),
    "blood_glucose_mg_dl": _MetricSourceCatalogEntry(
        metric_key="blood_glucose_mg_dl",
        source_model="raw_aggregate",
        related_type_keys=("blood_glucose",),
        aggregate_hint="latest_sample",
        description="Latest blood glucose sample in the day.",
    ),
    "body_temperature_celsius": _MetricSourceCatalogEntry(
        metric_key="body_temperature_celsius",
        source_model="raw_aggregate",
        related_type_keys=("body_temperature",),
        aggregate_hint="latest_sample",
        description="Latest body temperature sample in the day.",
    ),
    "basal_body_temperature_celsius": _MetricSourceCatalogEntry(
        metric_key="basal_body_temperature_celsius",
        source_model="raw_aggregate",
        related_type_keys=("basal_body_temperature",),
        aggregate_hint="latest_sample",
        description="Latest basal body temperature sample in the day.",
    ),
    "sleep_asleep_minutes": _MetricSourceCatalogEntry(
        metric_key="sleep_asleep_minutes",
        source_model="raw_aggregate",
        related_type_keys=("sleep_analysis",),
        aggregate_hint="category_minutes_per_day",
        description="Minutes derived from sleep analysis categories marked asleep.",
    ),
    "sleep_in_bed_minutes": _MetricSourceCatalogEntry(
        metric_key="sleep_in_bed_minutes",
        source_model="raw_aggregate",
        related_type_keys=("sleep_analysis",),
        aggregate_hint="category_minutes_per_day",
        description="Minutes derived from sleep analysis categories marked in bed.",
    ),
}

_DEFAULT_ANALYSIS_METRIC_KEYS: tuple[str, ...] = tuple(_METRIC_SOURCE_CATALOG.keys())
_NOTABLE_ANALYSIS_METRIC_KEYS: tuple[str, ...] = (
    "steps",
    "resting_hr_avg",
    "hrv_sdnn_avg",
    "oxygen_saturation_pct",
    "respiratory_rate_avg",
    "sleep_asleep_minutes",
)


class _DataNotFound(Exception):
    pass


def _raise(code: str, message: str) -> None:
    raise ToolError(f"{code}: {message}")


def _parse_ymd(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError as exc:
        raise ToolError(f"INVALID_ARGUMENTS: invalid date (expected YYYY-MM-DD): {value}") from exc


def _parse_yyyy_mm(value: str) -> tuple[int, int]:
    try:
        year_text, month_text = value.split("-", maxsplit=1)
        year = int(year_text)
        month = int(month_text)
    except Exception as exc:  # pragma: no cover
        raise ToolError(f"INVALID_ARGUMENTS: invalid month (expected YYYY-MM): {value}") from exc
    if not (1 <= month <= 12):
        _raise("INVALID_ARGUMENTS", f"invalid month: {value}")
    return year, month


def _iter_months(start: dt.date, end: dt.date) -> list[str]:
    months: list[str] = []
    year, month = start.year, start.month
    while (year, month) <= (end.year, end.month):
        months.append(f"{year:04d}-{month:02d}")
        month += 1
        if month == 13:
            year += 1
            month = 1
    return months


def _posix_join(*parts: str) -> str:
    cleaned: list[str] = []
    for part in parts:
        if not part:
            continue
        cleaned.append(part.strip("/"))
    return "/".join(cleaned)


def _json_loads_dict(raw: bytes, relpath: str) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ToolError(f"INTERNAL: failed to parse JSON: {relpath}") from exc
    if not isinstance(value, dict):
        raise ToolError(f"INTERNAL: unexpected JSON type for {relpath}")
    return value


class _HealthS3ConfigModel(BaseModel):
    model_config = ConfigDict(extra="ignore")

    endpoint: str = ""
    region: str = "auto"
    bucket: str = ""
    prefix: str = ""
    access_key_id: str = ""
    secret_access_key: str = ""
    session_token: str | None = None
    use_path_style: bool = True


class _HealthConfigModel(BaseModel):
    model_config = ConfigDict(extra="ignore")

    # Keep these as strings so we can emit an explicit deprecation message for old configs.
    storage_backend: str | None = None
    icloud_root: str | None = None
    s3: _HealthS3ConfigModel = Field(default_factory=_HealthS3ConfigModel)


class _AppConfigModel(BaseModel):
    model_config = ConfigDict(extra="ignore")

    health: _HealthConfigModel = Field(default_factory=_HealthConfigModel)


def _config_path() -> Path:
    override = (os.getenv("NUCLEUS_APPLE_MCP_CONFIG") or "").strip()
    if override:
        return Path(os.path.expanduser(override)).resolve()
    return Path.home() / ".config" / "nucleus-apple-mcp" / "config.toml"


@lru_cache(maxsize=1)
def _load_app_config() -> _AppConfigModel:
    path = _config_path()
    if not path.exists():
        return _AppConfigModel()

    try:
        with path.open("rb") as handle:
            value = tomllib.load(handle)
    except OSError as exc:
        raise ToolError(f"STORAGE_UNAVAILABLE: failed to read MCP config: {path}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ToolError(f"INVALID_ARGUMENTS: invalid TOML in MCP config: {path}") from exc

    try:
        return _AppConfigModel.model_validate(value)
    except ValidationError as exc:
        raise ToolError(f"INVALID_ARGUMENTS: invalid MCP config schema: {path}: {exc}") from exc


def _configured_storage_backend() -> _StorageBackendName | None:
    raw = (os.getenv("NUCLEUS_HEALTH_STORAGE_BACKEND") or "").strip()
    if not raw:
        raw = (_load_app_config().health.storage_backend or "").strip()
    if not raw:
        return None
    if raw == "icloud_drive":
        _raise(
            "INVALID_ARGUMENTS",
            "the `icloud_drive` health backend has been removed. Configure `s3_object_store` instead.",
        )
    if raw not in {"auto", "s3_object_store"}:
        _raise("INVALID_ARGUMENTS", f"invalid storage backend in config: {raw}")
    return raw


class _StorageBackend(Protocol):
    def read_bytes(self, relpath: str) -> bytes: ...

    def list_keys(self, relprefix: str) -> list[str]: ...

    @property
    def backend(self) -> str: ...


@dataclass(frozen=True)
class _S3Config:
    endpoint: str
    region: str
    bucket: str
    prefix: str
    access_key_id: str
    secret_access_key: str
    session_token: str | None
    use_path_style: bool


def _bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _load_s3_config() -> _S3Config | None:
    s3_config = _load_app_config().health.s3

    endpoint = (os.getenv("NUCLEUS_HEALTH_S3_ENDPOINT") or s3_config.endpoint).strip()
    bucket = (os.getenv("NUCLEUS_HEALTH_S3_BUCKET") or s3_config.bucket).strip()
    access_key_id = (os.getenv("NUCLEUS_HEALTH_S3_ACCESS_KEY_ID") or s3_config.access_key_id).strip()
    secret_access_key = (os.getenv("NUCLEUS_HEALTH_S3_SECRET_ACCESS_KEY") or s3_config.secret_access_key).strip()

    if not endpoint or not bucket:
        return None
    if not access_key_id or not secret_access_key:
        _raise(
            "NOT_AUTHORIZED",
            "missing S3 credentials (set NUCLEUS_HEALTH_S3_ACCESS_KEY_ID and NUCLEUS_HEALTH_S3_SECRET_ACCESS_KEY).",
        )

    if "://" not in endpoint:
        endpoint = f"https://{endpoint}"

    return _S3Config(
        endpoint=endpoint,
        region=(os.getenv("NUCLEUS_HEALTH_S3_REGION") or s3_config.region or "auto").strip() or "auto",
        bucket=bucket,
        prefix=(os.getenv("NUCLEUS_HEALTH_S3_PREFIX") or s3_config.prefix).strip().strip("/"),
        access_key_id=access_key_id,
        secret_access_key=secret_access_key,
        session_token=(os.getenv("NUCLEUS_HEALTH_S3_SESSION_TOKEN") or (s3_config.session_token or "")).strip() or None,
        use_path_style=(
            _bool_env("NUCLEUS_HEALTH_S3_USE_PATH_STYLE", default=s3_config.use_path_style)
            if os.getenv("NUCLEUS_HEALTH_S3_USE_PATH_STYLE") is not None
            else s3_config.use_path_style
        ),
    )


def _rfc3986_quote(value: str, *, safe: str) -> str:
    return quote(value, safe=safe)


def _canonical_uri(*, bucket: str, key: str, use_path_style: bool) -> str:
    def encode_path(path: str) -> str:
        segments = [seg for seg in path.split("/") if seg]
        return "/".join(_rfc3986_quote(seg, safe="-_.~") for seg in segments)

    if use_path_style:
        encoded_bucket = _rfc3986_quote(bucket, safe="-_.~")
        encoded_key = encode_path(key)
        return f"/{encoded_bucket}" if not encoded_key else f"/{encoded_bucket}/{encoded_key}"
    encoded_key = encode_path(key)
    return "/" if not encoded_key else f"/{encoded_key}"


def _canonical_query(params: dict[str, str]) -> str:
    items = sorted(
        (_rfc3986_quote(key, safe="-_.~"), _rfc3986_quote(value, safe="-_.~"))
        for key, value in params.items()
    )
    return "&".join(f"{key}={value}" for key, value in items)


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hmac_sha256(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode("utf-8"), hashlib.sha256).digest()


class _S3Backend:
    def __init__(self, config: _S3Config) -> None:
        self._config = config
        self._client = httpx.Client(timeout=httpx.Timeout(20.0))

    @property
    def backend(self) -> str:
        return "s3_object_store"

    def _endpoint_parts(self) -> tuple[str, str, str | None]:
        parsed = urlparse(self._config.endpoint)
        scheme = parsed.scheme or "https"
        host = parsed.hostname or ""
        port = None if parsed.port is None else str(parsed.port)
        if not host:
            _raise("INVALID_ARGUMENTS", "invalid S3 endpoint")
        return scheme, host, port

    def _make_url(self, *, key: str, query: str = "") -> tuple[str, str, str]:
        scheme, base_host, port = self._endpoint_parts()
        hostport = f"{base_host}:{port}" if port else base_host
        canonical_uri = _canonical_uri(bucket=self._config.bucket, key=key, use_path_style=self._config.use_path_style)

        if self._config.use_path_style:
            url = f"{scheme}://{hostport}{canonical_uri}"
            host = hostport
        else:
            host = f"{self._config.bucket}.{hostport}"
            url = f"{scheme}://{host}{canonical_uri}"

        if query:
            url = f"{url}?{query}"
        return url, canonical_uri, host

    def _sign_headers(self, *, method: str, host: str, canonical_uri: str, query: str) -> dict[str, str]:
        now = dt.datetime.now(dt.timezone.utc)
        amz_date = now.strftime("%Y%m%dT%H%M%SZ")
        date_stamp = now.strftime("%Y%m%d")
        region = self._config.region or "auto"
        payload_hash = _sha256_hex(b"")

        lower_headers: dict[str, str] = {
            "host": host,
            "x-amz-content-sha256": payload_hash,
            "x-amz-date": amz_date,
        }
        if self._config.session_token:
            lower_headers["x-amz-security-token"] = self._config.session_token

        signed_header_names = sorted(lower_headers.keys())
        canonical_headers = "".join(f"{name}:{lower_headers[name].strip()}\n" for name in signed_header_names)
        signed_headers = ";".join(signed_header_names)

        canonical_request = "\n".join(
            [
                method,
                canonical_uri,
                query,
                canonical_headers,
                signed_headers,
                payload_hash,
            ]
        )
        scope = f"{date_stamp}/{region}/s3/aws4_request"
        string_to_sign = "\n".join(
            [
                "AWS4-HMAC-SHA256",
                amz_date,
                scope,
                _sha256_hex(canonical_request.encode("utf-8")),
            ]
        )

        k_date = _hmac_sha256(f"AWS4{self._config.secret_access_key}".encode("utf-8"), date_stamp)
        k_region = hmac.new(k_date, region.encode("utf-8"), hashlib.sha256).digest()
        k_service = hmac.new(k_region, b"s3", hashlib.sha256).digest()
        k_signing = hmac.new(k_service, b"aws4_request", hashlib.sha256).digest()
        signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

        headers = {
            "Host": host,
            "x-amz-date": amz_date,
            "x-amz-content-sha256": payload_hash,
            "Authorization": (
                f"AWS4-HMAC-SHA256 Credential={self._config.access_key_id}/{scope}, "
                f"SignedHeaders={signed_headers}, Signature={signature}"
            ),
        }
        if self._config.session_token:
            headers["x-amz-security-token"] = self._config.session_token
        return headers

    def _join_prefix(self, relpath: str) -> str:
        rel = relpath.strip("/")
        if not self._config.prefix:
            return rel
        return _posix_join(self._config.prefix, rel)

    def read_bytes(self, relpath: str) -> bytes:
        key = self._join_prefix(relpath)
        url, canonical_uri, host = self._make_url(key=key)
        headers = self._sign_headers(method="GET", host=host, canonical_uri=canonical_uri, query="")

        try:
            response = self._client.get(url, headers=headers)
        except httpx.HTTPError as exc:
            raise ToolError(f"STORAGE_UNAVAILABLE: S3 request failed: {exc}") from exc

        if response.status_code == 404:
            raise _DataNotFound(relpath)
        if response.status_code in {401, 403}:
            _raise("NOT_AUTHORIZED", "S3 request not authorized. Check credentials, bucket policy, and prefix.")
        if response.status_code >= 400:
            _raise("STORAGE_UNAVAILABLE", f"S3 GET failed ({response.status_code}).")
        return response.content

    def list_keys(self, relprefix: str) -> list[str]:
        prefix = self._join_prefix(relprefix.strip("/"))
        if prefix and not prefix.endswith("/"):
            prefix = f"{prefix}/"

        keys: list[str] = []
        continuation: str | None = None

        while True:
            params = {
                "list-type": "2",
                "max-keys": "1000",
                "prefix": prefix,
            }
            if continuation:
                params["continuation-token"] = continuation

            query = _canonical_query(params)
            url, canonical_uri, host = self._make_url(key="", query=query)
            headers = self._sign_headers(method="GET", host=host, canonical_uri=canonical_uri, query=query)

            try:
                response = self._client.get(url, headers=headers)
            except httpx.HTTPError as exc:
                raise ToolError(f"STORAGE_UNAVAILABLE: S3 list failed: {exc}") from exc

            if response.status_code in {401, 403}:
                _raise("NOT_AUTHORIZED", "S3 list not authorized. Check credentials, bucket policy, and prefix.")
            if response.status_code >= 400:
                _raise("STORAGE_UNAVAILABLE", f"S3 list failed ({response.status_code}).")

            try:
                root = ET.fromstring(response.content)
            except ET.ParseError as exc:
                raise ToolError("INTERNAL: failed to parse S3 list response") from exc

            for child in root:
                if child.tag.split("}")[-1] != "Contents":
                    continue
                key_text = None
                for field in child:
                    if field.tag.split("}")[-1] == "Key":
                        key_text = field.text
                        break
                if key_text:
                    keys.append(key_text)

            truncated = False
            for child in root:
                tag = child.tag.split("}")[-1]
                if tag == "IsTruncated":
                    truncated = child.text == "true"
                elif tag == "NextContinuationToken":
                    continuation = child.text
            if not truncated:
                break

        prefix_strip = f"{self._config.prefix.strip('/')}/" if self._config.prefix else ""
        relkeys: list[str] = []
        for key in keys:
            if prefix_strip and key.startswith(prefix_strip):
                relkeys.append(key[len(prefix_strip) :])
            else:
                relkeys.append(key)
        relkeys.sort()
        return relkeys


def _reject_removed_icloud_config() -> None:
    if (os.getenv("NUCLEUS_HEALTH_ICLOUD_ROOT") or "").strip():
        _raise(
            "INVALID_ARGUMENTS",
            "NUCLEUS_HEALTH_ICLOUD_ROOT is no longer supported. Configure S3-compatible storage instead.",
        )

    configured = (_load_app_config().health.icloud_root or "").strip()
    if configured:
        _raise(
            "INVALID_ARGUMENTS",
            "health.icloud_root is no longer supported. Configure `health.s3` instead.",
        )


def _resolve_storage_backend(backend: Literal["auto", "s3_object_store"]) -> _StorageBackend:
    _reject_removed_icloud_config()

    if backend == "s3_object_store":
        config = _load_s3_config()
        if not config:
            _raise(
                "NOT_AUTHORIZED",
                "S3 config missing. Set NUCLEUS_HEALTH_S3_ENDPOINT/BUCKET and credentials.",
            )
        return _S3Backend(config)

    preferred_backend = _configured_storage_backend()
    if preferred_backend and preferred_backend != "auto":
        return _resolve_storage_backend(preferred_backend)

    config = _load_s3_config()
    if config:
        return _S3Backend(config)

    _raise(
        "NOT_AUTHORIZED",
        "No supported storage configured. Set S3 env vars (ENDPOINT/BUCKET/ACCESS_KEY_ID/SECRET_ACCESS_KEY) or configure `health.s3`.",
    )
    raise AssertionError("unreachable")


def _daily_date_path(date: dt.date) -> str:
    return _posix_join("health", "daily", "dates", f"{date.isoformat()}.json")


def _daily_month_path(month: str) -> str:
    return _posix_join("health", "daily", "months", f"{month}.json")


def _raw_manifest_path(date: dt.date) -> str:
    return _posix_join("health", "raw", "dates", date.isoformat(), "manifest.json")


def _commit_prefix() -> str:
    return _posix_join("health", "commits") + "/"


def _read_json(backend: _StorageBackend, relpath: str) -> dict[str, Any]:
    return _json_loads_dict(backend.read_bytes(relpath), relpath)


def _read_daily_snapshot(date: dt.date, backend: _StorageBackend) -> dict[str, Any]:
    relpath = _daily_date_path(date)
    try:
        return _read_json(backend, relpath)
    except _DataNotFound as exc:
        raise _DataNotFound(date.isoformat()) from exc


def _read_month_index(month: str, backend: _StorageBackend) -> dict[str, Any] | None:
    relpath = _daily_month_path(month)
    try:
        return _read_json(backend, relpath)
    except _DataNotFound:
        return None


def _public_daily_snapshot(snapshot: dict[str, Any], backend_name: str) -> dict[str, Any]:
    return {
        "date": snapshot.get("date"),
        "commit_id": snapshot.get("commit_id"),
        "generated_at": snapshot.get("generated_at"),
        "day": snapshot.get("day"),
        "collector": snapshot.get("collector"),
        "metrics": snapshot.get("metrics"),
        "metric_status": snapshot.get("metric_status"),
        "metric_units": snapshot.get("metric_units"),
        "raw_manifest_relpath": snapshot.get("raw_manifest_relpath"),
        "schema_version": snapshot.get("schema_version"),
        "storage_backend": backend_name,
    }


def _read_raw_manifest(date: dt.date, backend: _StorageBackend) -> dict[str, Any]:
    relpath = _raw_manifest_path(date)
    try:
        return _read_json(backend, relpath)
    except _DataNotFound as exc:
        raise _DataNotFound(date.isoformat()) from exc


def _iter_dates(start: dt.date, end: dt.date) -> list[dt.date]:
    dates: list[dt.date] = []
    cursor = start
    while cursor <= end:
        dates.append(cursor)
        cursor += dt.timedelta(days=1)
    return dates


def _manifest_types(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    types = manifest.get("types")
    if not isinstance(types, dict):
        raise ToolError("INTERNAL: raw manifest missing types")
    return {str(key): value for key, value in types.items() if isinstance(value, dict)}


def _public_raw_manifest(manifest: dict[str, Any], *, backend_name: str, relpath: str, type_keys: list[str] | None = None) -> dict[str, Any]:
    types = _manifest_types(manifest)
    if type_keys is not None:
        selected = {key: types[key] for key in type_keys if key in types}
    else:
        selected = dict(types)

    return {
        "date": manifest.get("date"),
        "commit_id": manifest.get("commit_id"),
        "generated_at": manifest.get("generated_at"),
        "day": manifest.get("day"),
        "collector": manifest.get("collector"),
        "schema_version": manifest.get("schema_version"),
        "raw_manifest_relpath": relpath,
        "types": selected,
        "storage_backend": backend_name,
    }


def _normalize_type_keys(type_keys: list[str] | None) -> list[str]:
    if not type_keys:
        return []
    normalized: list[str] = []
    seen: set[str] = set()
    for raw in type_keys:
        value = raw.strip()
        if not value or value in seen:
            continue
        seen.add(value)
        normalized.append(value)
    return normalized


def _matching_catalog_type_keys(
    *,
    tags: list[HealthSampleTag] | None,
    kinds: list[HealthSampleKind] | None,
) -> set[str]:
    matched: set[str] = set()
    tag_set = set(tags or [])
    kind_set = set(kinds or [])

    for entry in _SAMPLE_CATALOG:
        if tag_set and not set(entry.tags).intersection(tag_set):
            continue
        if kind_set and entry.kind not in kind_set:
            continue
        matched.add(entry.type_key)
    return matched


def _select_manifest_type_keys(
    manifest: dict[str, Any],
    *,
    requested_type_keys: list[str],
    tags: list[HealthSampleTag] | None,
    kinds: list[HealthSampleKind] | None,
) -> list[str]:
    manifest_keys = sorted(_manifest_types(manifest).keys())

    if not requested_type_keys and not tags and not kinds:
        return manifest_keys

    selected = set(manifest_keys)
    if requested_type_keys:
        selected &= set(requested_type_keys)
    if tags or kinds:
        selected &= _matching_catalog_type_keys(tags=tags, kinds=kinds)
    return [key for key in manifest_keys if key in selected]


def _selection_signature(
    *,
    start_date: str,
    end_date: str,
    type_keys: list[str],
    tags: list[HealthSampleTag] | None,
    kinds: list[HealthSampleKind] | None,
) -> str:
    payload = {
        "start_date": start_date,
        "end_date": end_date,
        "type_keys": type_keys,
        "tags": sorted(tag.value for tag in (tags or [])),
        "kinds": sorted(kind.value for kind in (kinds or [])),
    }
    return _sha256_hex(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))[:16]


def _encode_cursor(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_cursor(cursor: str) -> dict[str, Any]:
    padding = "=" * (-len(cursor) % 4)
    try:
        raw = base64.urlsafe_b64decode(cursor + padding)
        value = json.loads(raw)
    except Exception as exc:  # pragma: no cover
        raise ToolError("INVALID_ARGUMENTS: invalid cursor") from exc
    if not isinstance(value, dict):
        raise ToolError("INVALID_ARGUMENTS: invalid cursor payload")
    return value


def _parse_jsonl_page(raw: bytes, *, offset: int, max_records: int) -> tuple[list[dict[str, Any]], int, bool]:
    if max_records <= 0:
        return [], offset, False

    samples: list[dict[str, Any]] = []
    sample_index = 0
    for line in raw.splitlines():
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(value, dict) or value.get("record") != "sample":
            continue
        if sample_index < offset:
            sample_index += 1
            continue
        if len(samples) >= max_records:
            return samples, sample_index, True
        samples.append(value)
        sample_index += 1
    return samples, sample_index, False


@dataclass(frozen=True)
class _ManifestContext:
    date: dt.date
    relpath: str
    manifest: dict[str, Any]
    selected_type_keys: list[str]


def _type_has_readable_data(type_info: dict[str, Any]) -> bool:
    relpath = type_info.get("relpath")
    return isinstance(relpath, str) and bool(relpath)


def _build_next_samples_cursor(
    contexts: list[_ManifestContext],
    *,
    current_context_index: int,
    current_type_index: int,
    next_offset: int,
    has_more_in_current_type: bool,
    current_type_key: str,
    query_signature: str,
) -> str | None:
    if has_more_in_current_type:
        return _encode_cursor(
            {
                "v": 1,
                "query": query_signature,
                "date": contexts[current_context_index].date.isoformat(),
                "type_key": current_type_key,
                "offset": next_offset,
            }
        )

    current_manifest_types = _manifest_types(contexts[current_context_index].manifest)
    for type_key in contexts[current_context_index].selected_type_keys[current_type_index + 1 :]:
        type_info = current_manifest_types.get(type_key)
        if isinstance(type_info, dict) and _type_has_readable_data(type_info):
            return _encode_cursor(
                {
                    "v": 1,
                    "query": query_signature,
                    "date": contexts[current_context_index].date.isoformat(),
                    "type_key": type_key,
                    "offset": 0,
                }
            )

    for context in contexts[current_context_index + 1 :]:
        manifest_types = _manifest_types(context.manifest)
        for type_key in context.selected_type_keys:
            type_info = manifest_types.get(type_key)
            if isinstance(type_info, dict) and _type_has_readable_data(type_info):
                return _encode_cursor(
                    {
                        "v": 1,
                        "query": query_signature,
                        "date": context.date.isoformat(),
                        "type_key": type_key,
                        "offset": 0,
                    }
                )
    return None


def _public_sample_catalog() -> dict[str, Any]:
    return {
        "kinds": [kind.value for kind in HealthSampleKind],
        "tags": [tag.value for tag in HealthSampleTag],
        "sample_types": [
            {
                "type_key": entry.type_key,
                "kind": entry.kind.value,
                "tags": [tag.value for tag in entry.tags],
                "description": entry.description,
                "unit": entry.unit,
                "related_metric_keys": list(entry.related_metric_keys),
                "aggregate_hint": entry.aggregate_hint,
            }
            for entry in _SAMPLE_CATALOG
        ],
        "metrics": [
            {
                "metric_key": entry.metric_key,
                "source_model": entry.source_model,
                "related_type_keys": list(entry.related_type_keys),
                "aggregate_hint": entry.aggregate_hint,
                "description": entry.description,
            }
            for entry in _METRIC_SOURCE_CATALOG.values()
        ],
    }


def _read_samples_impl(
    *,
    start_date: str,
    end_date: str,
    type_keys: list[str] | None,
    tags: list[HealthSampleTag] | None,
    kinds: list[HealthSampleKind] | None,
    cursor: str | None,
    max_records: int,
    manifest_only: bool,
    include_manifests: bool,
    storage_backend: _StorageBackendName,
) -> dict[str, Any]:
    start = _parse_ymd(start_date)
    end = _parse_ymd(end_date)
    if start > end:
        _raise("INVALID_ARGUMENTS", "start_date must be <= end_date.")
    if (end - start).days + 1 > 31:
        _raise("INVALID_ARGUMENTS", "raw sample range too large (max 31 days).")

    requested_type_keys = _normalize_type_keys(type_keys)
    query_signature = _selection_signature(
        start_date=start_date,
        end_date=end_date,
        type_keys=requested_type_keys,
        tags=tags,
        kinds=kinds,
    )

    cursor_date: str | None = None
    cursor_type_key: str | None = None
    cursor_offset = 0
    if cursor:
        payload = _decode_cursor(cursor)
        if payload.get("v") != 1 or payload.get("query") != query_signature:
            _raise("INVALID_ARGUMENTS", "cursor does not match this query.")
        raw_cursor_date = payload.get("date")
        raw_cursor_type_key = payload.get("type_key")
        if raw_cursor_date is not None and not isinstance(raw_cursor_date, str):
            _raise("INVALID_ARGUMENTS", "invalid cursor date")
        if raw_cursor_type_key is not None and not isinstance(raw_cursor_type_key, str):
            _raise("INVALID_ARGUMENTS", "invalid cursor type_key")
        try:
            cursor_offset = int(payload.get("offset") or 0)
        except (TypeError, ValueError) as exc:
            raise ToolError("INVALID_ARGUMENTS: invalid cursor offset") from exc
        if cursor_offset < 0:
            _raise("INVALID_ARGUMENTS", "invalid cursor offset")
        cursor_date = raw_cursor_date
        cursor_type_key = raw_cursor_type_key

    backend = _resolve_storage_backend(storage_backend)

    contexts: list[_ManifestContext] = []
    missing_dates: list[str] = []
    manifest_views: list[dict[str, Any]] = []

    for day in _iter_dates(start, end):
        relpath = _raw_manifest_path(day)
        try:
            manifest = _read_raw_manifest(day, backend)
        except _DataNotFound:
            missing_dates.append(day.isoformat())
            continue
        selected_type_keys = _select_manifest_type_keys(
            manifest,
            requested_type_keys=requested_type_keys,
            tags=tags,
            kinds=kinds,
        )
        contexts.append(
            _ManifestContext(
                date=day,
                relpath=relpath,
                manifest=manifest,
                selected_type_keys=selected_type_keys,
            )
        )
        if include_manifests or manifest_only:
            manifest_views.append(
                _public_raw_manifest(
                    manifest,
                    backend_name=backend.backend,
                    relpath=relpath,
                    type_keys=selected_type_keys,
                )
            )

    samples: list[dict[str, Any]] = []
    next_cursor: str | None = None

    if not manifest_only and max_records > 0:
        for context_index, context in enumerate(contexts):
            if cursor_date and context.date.isoformat() < cursor_date:
                continue

            manifest_types = _manifest_types(context.manifest)
            for type_index, type_key in enumerate(context.selected_type_keys):
                if cursor_date == context.date.isoformat() and cursor_type_key and type_key < cursor_type_key:
                    continue

                type_info = manifest_types.get(type_key)
                if not isinstance(type_info, dict):
                    continue
                relpath = type_info.get("relpath")
                if not isinstance(relpath, str) or not relpath:
                    continue

                offset = 0
                if cursor_date == context.date.isoformat() and cursor_type_key == type_key:
                    offset = cursor_offset

                remaining = max_records - len(samples)
                if remaining <= 0:
                    next_cursor = _build_next_samples_cursor(
                        contexts,
                        current_context_index=context_index,
                        current_type_index=type_index,
                        next_offset=offset,
                        has_more_in_current_type=True,
                        current_type_key=type_key,
                        query_signature=query_signature,
                    )
                    break

                try:
                    raw = backend.read_bytes(relpath)
                except _DataNotFound:
                    continue

                page_samples, next_offset, has_more_in_current_type = _parse_jsonl_page(
                    raw,
                    offset=offset,
                    max_records=remaining,
                )
                samples.extend(page_samples)

                if len(samples) >= max_records:
                    next_cursor = _build_next_samples_cursor(
                        contexts,
                        current_context_index=context_index,
                        current_type_index=type_index,
                        next_offset=next_offset,
                        has_more_in_current_type=has_more_in_current_type,
                        current_type_key=type_key,
                        query_signature=query_signature,
                    )
                    break
            if next_cursor:
                break

    return {
        "start_date": start_date,
        "end_date": end_date,
        "storage_backend": backend.backend,
        "selected_type_keys": requested_type_keys or None,
        "selected_tags": [tag.value for tag in (tags or [])] or None,
        "selected_kinds": [kind.value for kind in (kinds or [])] or None,
        "manifests": manifest_views if (include_manifests or manifest_only) else [],
        "samples": samples,
        "missing_dates": missing_dates,
        "truncated": next_cursor is not None,
        "next_cursor": next_cursor,
    }


def _metric_diagnosis(
    *,
    metric_key: str,
    metric_status: str | None,
    related_raw_types: dict[str, dict[str, Any]],
) -> tuple[str, str]:
    if metric_status == "ok":
        return "available", "Daily metric is present."
    if metric_status == "unsupported":
        return "unsupported", "This metric is unsupported by the current exporter or device."
    if metric_status == "unauthorized":
        return "unauthorized", "HealthKit authorization is missing for this metric or its source data."

    source = _METRIC_SOURCE_CATALOG.get(metric_key)
    if source is None:
        return "unknown", "No source mapping is defined for this metric."

    raw_statuses = {
        key: (
            (info.get("status") if isinstance(info.get("status"), str) else None),
            int(info.get("record_count") or 0),
        )
        for key, info in related_raw_types.items()
    }

    if source.source_model == "activity_summary":
        if any(status == "unauthorized" for status, _ in raw_statuses.values()):
            return "activity_summary_unauthorized", "Supporting raw types include unauthorized data; Activity Summary may also be unavailable."
        if any(count > 0 for _, count in raw_statuses.values()):
            return (
                "activity_summary_gap",
                "Supporting raw samples exist, but this metric is derived from HKActivitySummary and can still be no_data if summary access/data is unavailable.",
            )
        return "activity_summary_no_data", "No supporting raw samples were found for this activity-summary metric."

    if any(status == "unauthorized" for status, _ in raw_statuses.values()):
        return "raw_unauthorized", "Related raw types are unauthorized, so the daily aggregate could not be computed."
    if not raw_statuses:
        return "raw_type_missing", "No mapped raw type was found in the manifest for this metric."
    if any(count > 0 for _, count in raw_statuses.values()):
        return "aggregation_gap", "Related raw samples exist, but the daily aggregate is still no_data. This indicates an exporter aggregation gap or schema mismatch."
    return "raw_no_data", "Related raw types are present but contain no records for this day."


def _inspect_day_impl(
    *,
    date: str,
    metric_keys: list[str] | None,
    type_keys: list[str] | None,
    storage_backend: _StorageBackendName,
) -> dict[str, Any]:
    day = _parse_ymd(date)
    backend = _resolve_storage_backend(storage_backend)

    try:
        snapshot = _read_daily_snapshot(day, backend)
    except _DataNotFound:
        _raise("DATA_NOT_FOUND", f"No daily metrics found for {date}.")

    try:
        manifest = _read_raw_manifest(day, backend)
    except _DataNotFound:
        _raise("DATA_NOT_FOUND", f"No raw manifest found for {date}.")

    requested_metrics = _normalize_type_keys(metric_keys)
    requested_types = _normalize_type_keys(type_keys)

    if requested_metrics:
        metric_keys_to_inspect = requested_metrics
    elif requested_types:
        metric_keys_to_inspect = [
            metric_key
            for metric_key, source in _METRIC_SOURCE_CATALOG.items()
            if set(source.related_type_keys).intersection(requested_types)
        ]
    else:
        metric_keys_to_inspect = list(_METRIC_SOURCE_CATALOG.keys())

    metrics = snapshot.get("metrics") if isinstance(snapshot.get("metrics"), dict) else {}
    metric_status = snapshot.get("metric_status") if isinstance(snapshot.get("metric_status"), dict) else {}
    metric_units = snapshot.get("metric_units") if isinstance(snapshot.get("metric_units"), dict) else {}
    manifest_types = _manifest_types(manifest)

    inspection: list[dict[str, Any]] = []
    for metric_key in metric_keys_to_inspect:
        source = _METRIC_SOURCE_CATALOG.get(metric_key)
        if source is None:
            continue
        related_raw_types = {
            type_key: manifest_types[type_key]
            for type_key in source.related_type_keys
            if type_key in manifest_types and (not requested_types or type_key in requested_types)
        }
        diagnosis_code, diagnosis_message = _metric_diagnosis(
            metric_key=metric_key,
            metric_status=metric_status.get(metric_key) if isinstance(metric_status.get(metric_key), str) else None,
            related_raw_types=related_raw_types,
        )
        inspection.append(
            {
                "metric_key": metric_key,
                "value": metrics.get(metric_key),
                "status": metric_status.get(metric_key),
                "unit": metric_units.get(metric_key),
                "source_model": source.source_model,
                "aggregate_hint": source.aggregate_hint,
                "description": source.description,
                "related_type_keys": list(source.related_type_keys),
                "related_raw_types": related_raw_types,
                "diagnosis": {
                    "code": diagnosis_code,
                    "message": diagnosis_message,
                },
            }
        )

    manifest_view = _public_raw_manifest(
        manifest,
        backend_name=backend.backend,
        relpath=_raw_manifest_path(day),
        type_keys=requested_types or None,
    )

    return {
        "date": date,
        "storage_backend": backend.backend,
        "snapshot": _public_daily_snapshot(snapshot, backend.backend),
        "manifest": manifest_view,
        "metrics": inspection,
    }


@dataclass(frozen=True)
class _MetricObservation:
    date: str
    value: float


def _read_range_metrics_impl(
    *,
    start_date: str,
    end_date: str,
    storage_backend: _StorageBackendName,
) -> dict[str, Any]:
    start = _parse_ymd(start_date)
    end = _parse_ymd(end_date)
    if start > end:
        _raise("INVALID_ARGUMENTS", "start_date must be <= end_date.")

    span = (end - start).days + 1
    if span > 366:
        _raise("INVALID_ARGUMENTS", "range too large (max 366 days).")

    backend = _resolve_storage_backend(storage_backend)

    snapshots_by_date: dict[str, dict[str, Any]] = {}
    for month in _iter_months(start, end):
        month_index = _read_month_index(month, backend)
        if not month_index:
            continue
        days = month_index.get("days")
        if not isinstance(days, list):
            continue
        for item in days:
            if not isinstance(item, dict):
                continue
            date_value = item.get("date")
            if isinstance(date_value, str):
                snapshots_by_date[date_value] = item

    data: list[dict[str, Any]] = []
    missing_dates: list[str] = []

    cursor = start
    while cursor <= end:
        ymd = cursor.isoformat()
        snapshot = snapshots_by_date.get(ymd)
        if snapshot is None:
            missing_dates.append(ymd)
        else:
            data.append(_public_daily_snapshot(snapshot, backend.backend))
        cursor += dt.timedelta(days=1)

    return {
        "start_date": start_date,
        "end_date": end_date,
        "storage_backend": backend.backend,
        "data": data,
        "missing_dates": missing_dates,
    }


def _coerce_numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        result = float(value)
        if math.isfinite(result):
            return result
    return None


def _rounded(value: float | None) -> float | None:
    if value is None:
        return None
    rounded = round(value, 2)
    if rounded == -0.0:
        return 0.0
    return rounded


def _metric_unit_from_snapshots(snapshots: list[dict[str, Any]], metric_key: str) -> str | None:
    for snapshot in snapshots:
        metric_units = snapshot.get("metric_units")
        if not isinstance(metric_units, dict):
            continue
        unit = metric_units.get(metric_key)
        if isinstance(unit, str) and unit:
            return unit
    return None


def _metric_status_counts(snapshots: list[dict[str, Any]], metric_key: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for snapshot in snapshots:
        metric_status = snapshot.get("metric_status")
        if not isinstance(metric_status, dict):
            continue
        status = metric_status.get(metric_key)
        if not isinstance(status, str) or not status:
            continue
        counts[status] = counts.get(status, 0) + 1
    return dict(sorted(counts.items()))


def _metric_value_is_plausible(snapshot: dict[str, Any], metric_key: str, value: float) -> bool:
    metrics = snapshot.get("metrics") if isinstance(snapshot.get("metrics"), dict) else {}
    if metric_key == "steps":
        return 0 <= value <= 100_000
    if metric_key == "resting_hr_avg":
        return 20 <= value <= 220
    if metric_key == "hrv_sdnn_avg":
        return 0 < value <= 300
    if metric_key == "vo2_max":
        return 5 <= value <= 100
    if metric_key == "oxygen_saturation_pct":
        return 70 <= value <= 100
    if metric_key == "respiratory_rate_avg":
        return 5 <= value <= 40
    if metric_key == "sleep_asleep_minutes":
        in_bed = _coerce_numeric(metrics.get("sleep_in_bed_minutes"))
        if not 60 <= value <= 1080:
            return False
        if in_bed is not None and value > in_bed + 60:
            return False
        return True
    if metric_key == "sleep_in_bed_minutes":
        asleep = _coerce_numeric(metrics.get("sleep_asleep_minutes"))
        if not 60 <= value <= 1440:
            return False
        if asleep is not None and asleep > value + 60:
            return False
        return True
    if metric_key == "body_mass_kg":
        return 20 <= value <= 500
    if metric_key == "body_fat_percentage":
        return 1 <= value <= 80
    if metric_key in {"blood_pressure_systolic_mmhg", "blood_pressure_diastolic_mmhg"}:
        return 20 <= value <= 300
    if metric_key == "blood_glucose_mg_dl":
        return 20 <= value <= 500
    if metric_key == "wrist_temperature_celsius":
        return -10 <= value <= 10
    if metric_key in {"body_temperature_celsius", "basal_body_temperature_celsius"}:
        return 25 <= value <= 45
    return True


def _metric_observations(
    snapshots: list[dict[str, Any]],
    metric_key: str,
) -> tuple[list[_MetricObservation], list[dict[str, Any]]]:
    observations: list[_MetricObservation] = []
    excluded_dates: list[dict[str, Any]] = []
    for snapshot in snapshots:
        metrics = snapshot.get("metrics")
        if not isinstance(metrics, dict):
            continue
        value = _coerce_numeric(metrics.get(metric_key))
        if value is None:
            continue
        if not _metric_value_is_plausible(snapshot, metric_key, value):
            excluded_dates.append(
                {
                    "date": snapshot.get("date"),
                    "value": _rounded(value),
                    "reason": "implausible_value",
                }
            )
            continue
        date_value = snapshot.get("date")
        if not isinstance(date_value, str):
            continue
        observations.append(_MetricObservation(date=date_value, value=value))
    return observations, excluded_dates


def _segment_ranges(start: dt.date, end: dt.date, segment_count: int) -> list[tuple[dt.date, dt.date]]:
    dates = _iter_dates(start, end)
    if not dates:
        return []
    bounded_count = max(1, min(segment_count, len(dates)))
    base_size = len(dates) // bounded_count
    remainder = len(dates) % bounded_count

    segments: list[tuple[dt.date, dt.date]] = []
    index = 0
    for segment_index in range(bounded_count):
        size = base_size + (1 if segment_index < remainder else 0)
        segment_dates = dates[index : index + size]
        segments.append((segment_dates[0], segment_dates[-1]))
        index += size
    return segments


def _quartile_summary(values: list[float]) -> tuple[float, float, float] | None:
    if len(values) < 4:
        return None
    try:
        q1, q2, q3 = quantiles(values, n=4, method="inclusive")
    except StatisticsError:
        return None
    return q1, q2, q3


def _segment_mean(
    observations: list[_MetricObservation],
    segment_start: dt.date,
    segment_end: dt.date,
) -> tuple[int, float | None]:
    segment_start_str = segment_start.isoformat()
    segment_end_str = segment_end.isoformat()
    values = [item.value for item in observations if segment_start_str <= item.date <= segment_end_str]
    if not values:
        return 0, None
    return len(values), mean(values)


def _metric_trend_summary(
    observations: list[_MetricObservation],
    segments: list[tuple[dt.date, dt.date]],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    segment_payload: list[dict[str, Any]] = []
    segment_stats: list[tuple[int, float | None]] = []
    for segment_start, segment_end in segments:
        count, segment_mean_value = _segment_mean(observations, segment_start, segment_end)
        segment_stats.append((count, segment_mean_value))
        segment_payload.append(
            {
                "start_date": segment_start.isoformat(),
                "end_date": segment_end.isoformat(),
                "available_days": count,
                "mean": _rounded(segment_mean_value),
            }
        )

    valid_segments = [(count, value) for count, value in segment_stats if value is not None]
    if len(valid_segments) < 2:
        return segment_payload, {
            "direction": "insufficient_data",
            "delta": None,
            "delta_pct": None,
        }

    first_count, first_mean = valid_segments[0]
    last_count, last_mean = valid_segments[-1]
    if first_count < 2 or last_count < 2:
        return segment_payload, {
            "direction": "insufficient_data",
            "delta": None,
            "delta_pct": None,
        }

    median_value = median([item.value for item in observations])
    spread = max(item.value for item in observations) - min(item.value for item in observations)
    threshold = max(abs(median_value) * 0.01, spread * 0.1, 0.1)
    delta = last_mean - first_mean
    if abs(delta) < threshold:
        direction = "stable"
    elif delta > 0:
        direction = "up"
    else:
        direction = "down"

    delta_pct = None
    if abs(first_mean) > 1e-9:
        delta_pct = (delta / first_mean) * 100

    return segment_payload, {
        "direction": direction,
        "delta": _rounded(delta),
        "delta_pct": _rounded(delta_pct),
    }


def _metric_summary(
    *,
    metric_key: str,
    snapshots: list[dict[str, Any]],
    segments: list[tuple[dt.date, dt.date]],
    requested_days: int,
) -> dict[str, Any] | None:
    observations, excluded_dates = _metric_observations(snapshots, metric_key)
    if not observations:
        return None

    values = [item.value for item in observations]
    segment_payload, trend_payload = _metric_trend_summary(observations, segments)
    min_observation = min(observations, key=lambda item: item.value)
    max_observation = max(observations, key=lambda item: item.value)
    latest_observation = max(observations, key=lambda item: item.date)
    earliest_observation = min(observations, key=lambda item: item.date)

    return {
        "metric_key": metric_key,
        "unit": _metric_unit_from_snapshots(snapshots, metric_key),
        "available_days": len(observations),
        "requested_days": requested_days,
        "coverage_ratio": _rounded(len(observations) / requested_days) if requested_days > 0 else None,
        "status_counts": _metric_status_counts(snapshots, metric_key),
        "excluded_days": len(excluded_dates),
        "excluded_dates": excluded_dates[:10],
        "statistics": {
            "mean": _rounded(mean(values)),
            "median": _rounded(median(values)),
            "min": _rounded(min_observation.value),
            "min_date": min_observation.date,
            "max": _rounded(max_observation.value),
            "max_date": max_observation.date,
            "earliest": _rounded(earliest_observation.value),
            "earliest_date": earliest_observation.date,
            "latest": _rounded(latest_observation.value),
            "latest_date": latest_observation.date,
        },
        "trend": trend_payload,
        "segments": segment_payload,
    }


def _notable_reason_text(metric_key: str, direction: str) -> str:
    if metric_key == "steps":
        return "Lower-than-usual step volume." if direction == "low" else "Higher-than-usual step volume."
    if metric_key == "resting_hr_avg":
        return "Elevated resting heart rate." if direction == "high" else "Lower-than-usual resting heart rate."
    if metric_key == "hrv_sdnn_avg":
        return "Suppressed HRV." if direction == "low" else "Higher-than-usual HRV."
    if metric_key == "oxygen_saturation_pct":
        return "Lower-than-usual oxygen saturation." if direction == "low" else "Higher-than-usual oxygen saturation."
    if metric_key == "respiratory_rate_avg":
        return "Elevated respiratory rate." if direction == "high" else "Lower-than-usual respiratory rate."
    if metric_key == "sleep_asleep_minutes":
        return "Short sleep duration." if direction == "low" else "Long sleep duration."
    return "Notable deviation."


def _notable_days(
    snapshots: list[dict[str, Any]],
    metric_summaries: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    baselines: dict[str, dict[str, float]] = {}
    for metric_summary in metric_summaries:
        metric_key = metric_summary["metric_key"]
        if metric_key not in _NOTABLE_ANALYSIS_METRIC_KEYS:
            continue
        observations, _ = _metric_observations(snapshots, metric_key)
        quartile_summary = _quartile_summary([item.value for item in observations])
        if quartile_summary is None:
            continue
        q1, q2, q3 = quartile_summary
        iqr = q3 - q1
        fallback_scale = max(abs(q2) * 0.05, 1.0)
        baselines[metric_key] = {
            "q1": q1,
            "median": q2,
            "q3": q3,
            "scale": iqr if iqr > 0 else fallback_scale,
        }

    notable_days: list[dict[str, Any]] = []
    for snapshot in snapshots:
        metrics = snapshot.get("metrics")
        if not isinstance(metrics, dict):
            continue
        reasons: list[dict[str, Any]] = []
        score = 0.0
        for metric_key, baseline in baselines.items():
            raw_value = _coerce_numeric(metrics.get(metric_key))
            if raw_value is None or not _metric_value_is_plausible(snapshot, metric_key, raw_value):
                continue
            q1 = baseline["q1"]
            q3 = baseline["q3"]
            scale = baseline["scale"]
            lower = q1 - (1.5 * scale)
            upper = q3 + (1.5 * scale)
            if raw_value < lower:
                severity = (lower - raw_value) / scale
                reasons.append(
                    {
                        "metric_key": metric_key,
                        "direction": "low",
                        "value": _rounded(raw_value),
                        "baseline_median": _rounded(baseline["median"]),
                        "summary": _notable_reason_text(metric_key, "low"),
                        "severity": _rounded(severity),
                    }
                )
                score += severity
            elif raw_value > upper:
                severity = (raw_value - upper) / scale
                reasons.append(
                    {
                        "metric_key": metric_key,
                        "direction": "high",
                        "value": _rounded(raw_value),
                        "baseline_median": _rounded(baseline["median"]),
                        "summary": _notable_reason_text(metric_key, "high"),
                        "severity": _rounded(severity),
                    }
                )
                score += severity
        if reasons:
            notable_days.append(
                {
                    "date": snapshot.get("date"),
                    "score": _rounded(score),
                    "reasons": sorted(reasons, key=lambda item: item["severity"] or 0, reverse=True),
                }
            )

    notable_days.sort(key=lambda item: (item["score"] or 0), reverse=True)
    return notable_days[:7]


def _analysis_insights(
    metric_summaries: list[dict[str, Any]],
    *,
    missing_dates: list[str],
    requested_days: int,
) -> list[str]:
    insights: list[str] = []
    metric_summary_by_key = {item["metric_key"]: item for item in metric_summaries}

    steps_summary = metric_summary_by_key.get("steps")
    if steps_summary:
        direction = steps_summary["trend"]["direction"]
        if direction == "up":
            insights.append("Step volume trended up in the later segment.")
        elif direction == "down":
            insights.append("Step volume trended down in the later segment.")

    resting_hr_summary = metric_summary_by_key.get("resting_hr_avg")
    hrv_summary = metric_summary_by_key.get("hrv_sdnn_avg")
    if resting_hr_summary and hrv_summary:
        resting_direction = resting_hr_summary["trend"]["direction"]
        hrv_direction = hrv_summary["trend"]["direction"]
        if resting_direction == "down" and hrv_direction == "up":
            insights.append("Recovery markers improved in the later segment: resting HR fell while HRV rose.")
        elif resting_direction == "up" and hrv_direction == "down":
            insights.append("Recovery markers weakened in the later segment: resting HR rose while HRV fell.")
        elif resting_direction == "stable" and hrv_direction == "stable":
            insights.append("Recovery markers were broadly stable across the range.")

    oxygen_summary = metric_summary_by_key.get("oxygen_saturation_pct")
    if oxygen_summary:
        oxygen_stats = oxygen_summary["statistics"]
        oxygen_min = oxygen_stats.get("min")
        oxygen_max = oxygen_stats.get("max")
        if isinstance(oxygen_min, (int, float)) and isinstance(oxygen_max, (int, float)) and oxygen_max - oxygen_min <= 2:
            insights.append("Oxygen saturation stayed relatively stable.")

    vo2_summary = metric_summary_by_key.get("vo2_max")
    if vo2_summary and vo2_summary["available_days"] < 4:
        insights.append("VO2 max data is sparse; cardio-fitness trend confidence is low.")

    sleep_summaries = [
        item
        for item in metric_summaries
        if item["metric_key"] in {"sleep_asleep_minutes", "sleep_in_bed_minutes"} and item["excluded_days"] > 0
    ]
    if sleep_summaries:
        insights.append("Sleep metrics contain suspect dates and should be interpreted cautiously.")

    if missing_dates:
        insights.append(
            f"{len(missing_dates)} of {requested_days} requested dates are missing from exported daily snapshots."
        )

    return insights


def _analyze_range_impl(
    *,
    start_date: str,
    end_date: str,
    metric_keys: list[str] | None,
    segment_count: int,
    storage_backend: _StorageBackendName,
) -> dict[str, Any]:
    start = _parse_ymd(start_date)
    end = _parse_ymd(end_date)
    if start > end:
        _raise("INVALID_ARGUMENTS", "start_date must be <= end_date.")
    if not (1 <= segment_count <= 12):
        _raise("INVALID_ARGUMENTS", "segment_count must be between 1 and 12.")

    range_payload = _read_range_metrics_impl(
        start_date=start_date,
        end_date=end_date,
        storage_backend=storage_backend,
    )
    snapshots = range_payload["data"]
    missing_dates = range_payload["missing_dates"]
    requested_days = (end - start).days + 1
    segments = _segment_ranges(start, end, segment_count)

    requested_metric_keys = _normalize_type_keys(metric_keys) if metric_keys else list(_DEFAULT_ANALYSIS_METRIC_KEYS)
    metric_summaries: list[dict[str, Any]] = []
    for metric_key in requested_metric_keys:
        summary = _metric_summary(
            metric_key=metric_key,
            snapshots=snapshots,
            segments=segments,
            requested_days=requested_days,
        )
        if summary is not None:
            metric_summaries.append(summary)

    collectors = sorted(
        {
            collector.get("collector_id")
            for snapshot in snapshots
            for collector in [snapshot.get("collector")]
            if isinstance(collector, dict) and isinstance(collector.get("collector_id"), str)
        }
    )
    device_ids = sorted(
        {
            collector.get("device_id")
            for snapshot in snapshots
            for collector in [snapshot.get("collector")]
            if isinstance(collector, dict) and isinstance(collector.get("device_id"), str)
        }
    )
    commit_ids = sorted(
        {
            commit_id
            for snapshot in snapshots
            for commit_id in [snapshot.get("commit_id")]
            if isinstance(commit_id, str)
        }
    )

    return {
        "start_date": start_date,
        "end_date": end_date,
        "storage_backend": range_payload["storage_backend"],
        "read_strategy": {
            "uses_month_indexes_only": True,
            "raw_samples_read": False,
        },
        "days_requested": requested_days,
        "days_available": len(snapshots),
        "missing_dates": missing_dates,
        "collector_ids": collectors,
        "device_ids": device_ids,
        "latest_commit_id": commit_ids[-1] if commit_ids else None,
        "segment_count": len(segments),
        "metrics": metric_summaries,
        "notable_days": _notable_days(snapshots, metric_summaries),
        "insights": _analysis_insights(
            metric_summaries,
            missing_dates=missing_dates,
            requested_days=requested_days,
        ),
    }


@health_router.tool(
    name="health.read_daily_metrics",
    description="Read one day's exported Health metrics snapshot from an S3-compatible object store.",
)
def read_daily_metrics(
    date: Annotated[str, Field(description="Date (YYYY-MM-DD).")],
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    day = _parse_ymd(date)
    backend = _resolve_storage_backend(storage_backend)

    try:
        snapshot = _read_daily_snapshot(day, backend)
    except _DataNotFound:
        _raise("DATA_NOT_FOUND", f"No daily metrics found for {date}.")

    return _public_daily_snapshot(snapshot, backend.backend)


@health_router.tool(
    name="health.read_range_metrics",
    description="Read a date range of exported daily metrics using monthly indexes. Missing dates are reported, not treated as an error.",
)
def read_range_metrics(
    start_date: Annotated[str, Field(description="Start date (YYYY-MM-DD).")],
    end_date: Annotated[str, Field(description="End date (YYYY-MM-DD), inclusive.")],
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    return _read_range_metrics_impl(
        start_date=start_date,
        end_date=end_date,
        storage_backend=storage_backend,
    )


@health_router.tool(
    name="health.analyze_range",
    description="Analyze a Health date range using exported daily snapshots only. Returns metric summaries, segment trends, notable days, and brief insights without reading raw samples.",
)
def analyze_range(
    start_date: Annotated[str, Field(description="Start date (YYYY-MM-DD).")],
    end_date: Annotated[str, Field(description="End date (YYYY-MM-DD), inclusive.")],
    metric_keys: Annotated[
        list[str] | None,
        Field(description="Optional daily metric keys to analyze. Defaults to all known daily metrics with available data."),
    ] = None,
    segment_count: Annotated[
        int,
        Field(description="How many contiguous segments to split the requested range into for trend comparison.", ge=1, le=12),
    ] = 3,
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    return _analyze_range_impl(
        start_date=start_date,
        end_date=end_date,
        metric_keys=metric_keys,
        segment_count=segment_count,
        storage_backend=storage_backend,
    )


@health_router.tool(
    name="health.list_sample_catalog",
    description="List known Health raw sample types, kinds, tags, and how they relate to daily metrics.",
)
def list_sample_catalog() -> dict[str, Any]:
    return _public_sample_catalog()


@health_router.tool(
    name="health.read_samples",
    description="Read raw Health samples across one or more dates, filtered by type_keys/tags/kinds, with manifest-aware pagination.",
)
def read_samples(
    start_date: Annotated[str, Field(description="Start date (YYYY-MM-DD).")],
    end_date: Annotated[
        str | None,
        Field(description="End date (YYYY-MM-DD), inclusive. Defaults to start_date."),
    ] = None,
    type_keys: Annotated[
        list[str] | None,
        Field(description="Optional canonical raw type keys such as workout, heart_rate, or blood_pressure."),
    ] = None,
    tags: Annotated[
        list[HealthSampleTag] | None,
        Field(description="Optional logical tags. Matching is union-based across tags."),
    ] = None,
    kinds: Annotated[
        list[HealthSampleKind] | None,
        Field(description="Optional record kinds such as quantity, category, workout, or correlation."),
    ] = None,
    cursor: Annotated[
        str | None,
        Field(description="Opaque pagination cursor returned by a previous read_samples/read_daily_raw call."),
    ] = None,
    max_records: Annotated[
        int,
        Field(description="Maximum number of sample records to return.", ge=0, le=50000),
    ] = 5000,
    manifest_only: Annotated[
        bool,
        Field(description="When true, return only filtered manifest views and no sample payloads."),
    ] = False,
    include_manifests: Annotated[
        bool,
        Field(description="Include filtered manifest views alongside sample payloads."),
    ] = True,
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    final_end_date = end_date or start_date
    return _read_samples_impl(
        start_date=start_date,
        end_date=final_end_date,
        type_keys=type_keys,
        tags=tags,
        kinds=kinds,
        cursor=cursor,
        max_records=max_records,
        manifest_only=manifest_only,
        include_manifests=include_manifests,
        storage_backend=storage_backend,
    )


@health_router.tool(
    name="health.read_daily_raw",
    description="Read one day's raw Health samples. Prefer health.read_samples for range queries and richer filtering.",
)
def read_daily_raw(
    date: Annotated[str, Field(description="Date (YYYY-MM-DD).")],
    max_records: Annotated[
        int,
        Field(description="Maximum number of JSONL records to return (samples only).", ge=0, le=50000),
    ] = 5000,
    type_keys: Annotated[
        list[str] | None,
        Field(description="Optional canonical raw type keys such as workout, heart_rate, or blood_pressure."),
    ] = None,
    tags: Annotated[
        list[HealthSampleTag] | None,
        Field(description="Optional logical tags. Matching is union-based across tags."),
    ] = None,
    kinds: Annotated[
        list[HealthSampleKind] | None,
        Field(description="Optional record kinds such as quantity, category, workout, or correlation."),
    ] = None,
    cursor: Annotated[
        str | None,
        Field(description="Opaque pagination cursor returned by a previous read_samples/read_daily_raw call."),
    ] = None,
    manifest_only: Annotated[
        bool,
        Field(description="When true, return only the filtered manifest view."),
    ] = False,
    include_manifests: Annotated[
        bool,
        Field(description="Include the filtered manifest view in the response."),
    ] = True,
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    result = _read_samples_impl(
        start_date=date,
        end_date=date,
        type_keys=type_keys,
        tags=tags,
        kinds=kinds,
        cursor=cursor,
        max_records=max_records,
        manifest_only=manifest_only,
        include_manifests=include_manifests,
        storage_backend=storage_backend,
    )
    manifest = result["manifests"][0] if result["manifests"] else None
    return {
        "date": date,
        "commit_id": manifest.get("commit_id") if isinstance(manifest, dict) else None,
        "storage_backend": result["storage_backend"],
        "manifest": manifest,
        "samples": result["samples"],
        "truncated": result["truncated"],
        "next_cursor": result["next_cursor"],
        "selected_type_keys": result["selected_type_keys"],
        "selected_tags": result["selected_tags"],
        "selected_kinds": result["selected_kinds"],
    }


@health_router.tool(
    name="health.inspect_day",
    description="Inspect one day by combining the daily snapshot with the raw manifest, and explain metric/raw gaps.",
)
def inspect_day(
    date: Annotated[str, Field(description="Date (YYYY-MM-DD).")],
    metric_keys: Annotated[
        list[str] | None,
        Field(description="Optional daily metric keys to inspect."),
    ] = None,
    type_keys: Annotated[
        list[str] | None,
        Field(description="Optional raw type keys to focus the inspection on."),
    ] = None,
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    return _inspect_day_impl(
        date=date,
        metric_keys=metric_keys,
        type_keys=type_keys,
        storage_backend=storage_backend,
    )


@health_router.tool(
    name="health.list_changes",
    description="List health sync commits after an optional cursor, with optional per-date raw type details from raw manifests.",
)
def list_changes(
    since_cursor: Annotated[
        str | None,
        Field(description="Only return commits with commit_id greater than this cursor."),
    ] = None,
    limit: Annotated[
        int,
        Field(description="Maximum number of commits to return.", gt=0, le=1000),
    ] = 100,
    include_raw_types: Annotated[
        bool,
        Field(description="When true, enrich each changed date with raw type status/record_count/relpath from its manifest."),
    ] = True,
    storage_backend: Annotated[
        Literal["auto", "s3_object_store"],
        Field(description="Storage backend to read from."),
    ] = "auto",
) -> dict[str, Any]:
    backend = _resolve_storage_backend(storage_backend)
    keys = [key for key in backend.list_keys(_commit_prefix()) if key.endswith(".json")]

    commits: list[tuple[str, dict[str, Any]]] = []
    for key in keys:
        commit_id = key.rsplit("/", maxsplit=1)[-1].removesuffix(".json")
        if since_cursor and commit_id <= since_cursor:
            continue
        try:
            commit = _read_json(backend, key)
        except _DataNotFound:
            continue
        commits.append((commit_id, commit))

    commits.sort(key=lambda item: item[0])
    selected = commits[:limit]
    next_cursor = selected[-1][0] if selected else since_cursor

    changes: list[dict[str, Any]] = []
    for _, commit in selected:
        enriched_commit = dict(commit)
        dates = enriched_commit.get("dates")
        if include_raw_types and isinstance(dates, list):
            enriched_dates: list[dict[str, Any]] = []
            for item in dates:
                if not isinstance(item, dict):
                    continue
                enriched_item = dict(item)
                relpath = enriched_item.get("raw_manifest_relpath")
                if isinstance(relpath, str) and relpath:
                    try:
                        manifest = _read_json(backend, relpath)
                    except _DataNotFound:
                        enriched_item["raw_types"] = None
                    else:
                        enriched_item["raw_types"] = _manifest_types(manifest)
                else:
                    enriched_item["raw_types"] = None
                enriched_dates.append(enriched_item)
            enriched_commit["dates"] = enriched_dates
        changes.append(enriched_commit)

    return {
        "storage_backend": backend.backend,
        "since_cursor": since_cursor,
        "next_cursor": next_cursor,
        "changes": changes,
    }
