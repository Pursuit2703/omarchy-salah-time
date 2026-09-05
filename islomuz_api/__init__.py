from __future__ import annotations

import json
import os
import re
from datetime import date, datetime
from typing import Any
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

REGIONS_API = "https://new.islom.uz/api/v1/regions"
TAQVIM_URL = "https://www.islom.uz/taqvim/oylik"
BASE_DIR = os.path.dirname(__file__)
DEFAULT_CACHE_DIR = os.path.join(BASE_DIR, "data", "cache")
CACHE_DIR = os.environ.get("ISLOMUZ_CACHE_DIR", DEFAULT_CACHE_DIR)
DEFAULT_BROWSER_DIR = os.path.join(BASE_DIR, "data", "browsers")
PLAYWRIGHT_BROWSERS_PATH = os.environ.get(
    "PLAYWRIGHT_BROWSERS_PATH", DEFAULT_BROWSER_DIR
)
MAPS_DIR = os.path.join(BASE_DIR, "data", "maps")
CITY_NAME_MAP_PATH = os.path.join(MAPS_DIR, "city_name_map.json")
WEEKDAY_MAP_PATH = os.path.join(MAPS_DIR, "weekday_map.json")
PRAYER_MAP_PATH = os.path.join(MAPS_DIR, "prayer_map.json")

_PW = None
_BROWSER = None
_PAGE = None
_CITY_NAME_MAP = None

__all__ = [
    "get_regions",
    "find_region",
    "get_monthly_taqvim",
    "get_cached_monthly",
    "get_day",
    "get_today",
    "get_current_and_next",
    "prefetch_all_monthly",
    "prefetch_all_monthly_fast",
    "ensure_month_cache",
    "generate_city_name_map",
    "write_language_maps",
    "time_get_day",
    "close_playwright",
    "CACHE_DIR",
    "MAPS_DIR",
    "CITY_NAME_MAP_PATH",
    "WEEKDAY_MAP_PATH",
    "PRAYER_MAP_PATH",
]

RU_MONTHS = {
    1: "январь",
    2: "февраль",
    3: "март",
    4: "апрель",
    5: "май",
    6: "июнь",
    7: "июль",
    8: "август",
    9: "сентябрь",
    10: "октябрь",
    11: "ноябрь",
    12: "декабрь",
}

LATIN_MONTHS = {
    1: "yanvar",
    2: "fevral",
    3: "mart",
    4: "aprel",
    5: "may",
    6: "iyun",
    7: "iyul",
    8: "avgust",
    9: "sentyabr",
    10: "oktyabr",
    11: "noyabr",
    12: "dekabr",
}

RU_MONTH_NAME_TO_NUM = {v: k for k, v in RU_MONTHS.items()}
LATIN_MONTH_NAME_TO_NUM = {v: k for k, v in LATIN_MONTHS.items()}

HEADER_MAP = {
    "Сана": "date_day",
    "Ҳафта": "weekday",
    "Бомдод ( Саҳарлик тугаши )": "fajr",
    "Бомдод (Саҳарлик тугаши)": "fajr",
    "Қуёш": "sunrise",
    "Ишроқ": "ishraq",
    "Пешин": "dhuhr",
    "Аср": "asr",
    "Шом ( Ифторлик )": "maghrib",
    "Шом (Ифторлик)": "maghrib",
    "Хуфтон": "isha",
    "Таҳажжуд": "tahajjud",
    "Ҳижрий": "hijri_day",
    "Милодий": "gregorian",
}

HEADER_MAP_LATIN = {
    "Sana": "date_day",
    "Hafta": "weekday",
    "Bomdod": "fajr",
    "Bomdod ( Saharlik tugashi )": "fajr",
    "Bomdod (Saharlik tugashi)": "fajr",
    "Quyosh": "sunrise",
    "Ishroq": "ishraq",
    "Peshin": "dhuhr",
    "Asr": "asr",
    "Shom": "maghrib",
    "Shom ( Iftorlik )": "maghrib",
    "Shom (Iftorlik)": "maghrib",
    "Xufton": "isha",
    "Tahajjud": "tahajjud",
    "Hijriy": "hijri_day",
    "Milodiy": "gregorian",
}

WEEKDAY_CYR_TO_LATIN = {
    "Душанба": "Dushanba",
    "Сешанба": "Seshanba",
    "Чоршанба": "Chorshanba",
    "Пайшанба": "Payshanba",
    "Жума": "Juma",
    "Шанба": "Shanba",
    "Якшанба": "Yakshanba",
}

PRAYER_CYR_TO_LATIN = {
    "Бомдод": "Bomdod",
    "Қуёш": "Quyosh",
    "Ишроқ": "Ishroq",
    "Пешин": "Peshin",
    "Аср": "Asr",
    "Шом": "Shom",
    "Хуфтон": "Xufton",
    "Таҳажжуд": "Tahajjud",
}


def _fetch_json(url: str) -> Any:
    req = Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"})
    last_err = None
    for _ in range(3):
        try:
            with urlopen(req, timeout=20) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
            return json.loads(raw)
        except Exception as exc:
            last_err = exc
    raise last_err


def get_regions() -> list[dict]:
    """Return a de-duplicated list of region dicts from the API/cache."""
    try:
        data = _fetch_json(REGIONS_API)
    except Exception:
        # Fallback to cached regions if API is down.
        cached = _load_cache(os.path.join(CACHE_DIR, "regions.json"))
        if cached and isinstance(cached, list):
            data = cached
        else:
            raise
    regions: list[dict] = []
    # De-duplicate by canonical name to avoid repeats in downstream logic.
    seen_names: set[str] = set()
    for item in data:
        name = str(item["name"])
        if name in seen_names:
            continue
        seen_names.add(name)
        regions.append(
            {
                "id": int(item["id"]),
                "name": name,
                "name_ru": str(item.get("name_ru") or ""),
                "differ_minute": str(item.get("differ_minute") or "0"),
                "status": int(item.get("status") or 0),
                "latitude": str(item.get("latitude") or ""),
                "longitude": str(item.get("longitude") or ""),
            }
        )
    # Save de-duplicated snapshot for offline use.
    _save_cache(os.path.join(CACHE_DIR, "regions.json"), regions)
    return regions


def find_region(query: str) -> dict | None:
    """Return the best matching region dict for a city name query."""
    q = query.strip().lower()
    regions = get_regions()
    for region in regions:
        if region["name"].lower() == q or region["name_ru"].lower() == q:
            return region
    for region in regions:
        if q in region["name"].lower() or q in region["name_ru"].lower():
            return region
    # Try Latin -> Cyrillic transliteration for Uzbek
    q_cyr = latin_to_cyrillic(q)
    for region in regions:
        if q_cyr == region["name"].lower():
            return region
    for region in regions:
        if q_cyr and q_cyr in region["name"].lower():
            return region
    return None


def canonical_city_name(city_name: str) -> str:
    region = find_region(city_name)
    return region["name"] if region else city_name


def latin_to_cyrillic(text: str) -> str:
    # Uzbek Latin -> Cyrillic transliteration with case preservation.
    t = text

    # Normalize apostrophes.
    t = t.replace("’", "'").replace("ʻ", "'").replace("`", "'")

    def apply_case(src: str, dst: str) -> str:
        if src.isupper():
            return dst.upper()
        if src[:1].isupper():
            return dst[:1].upper() + dst[1:]
        return dst

    # Digraphs and special sequences first.
    seq = [
        ("o'", "ў"),
        ("g'", "ғ"),
        ("sh", "ш"),
        ("ch", "ч"),
        ("ng", "нг"),
        ("ya", "я"),
        ("yo", "ё"),
        ("yu", "ю"),
        ("ye", "е"),
    ]

    out = []
    i = 0
    while i < len(t):
        matched = False
        for s, d in seq:
            if t[i : i + len(s)].lower() == s:
                out.append(apply_case(t[i : i + len(s)], d))
                i += len(s)
                matched = True
                break
        if matched:
            continue
        ch = t[i]
        mapping = {
            "a": "а",
            "b": "б",
            "d": "д",
            "e": "е",
            "f": "ф",
            "g": "г",
            "h": "ҳ",
            "i": "и",
            "j": "ж",
            "k": "к",
            "l": "л",
            "m": "м",
            "n": "н",
            "o": "о",
            "p": "п",
            "q": "қ",
            "r": "р",
            "s": "с",
            "t": "т",
            "u": "у",
            "v": "в",
            "x": "х",
            "y": "й",
            "z": "з",
        }
        lower = ch.lower()
        if lower in mapping:
            out.append(apply_case(ch, mapping[lower]))
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def cyrillic_to_latin(text: str) -> str:
    t = text
    mapping = {
        "а": "a",
        "б": "b",
        "в": "v",
        "г": "g",
        "ғ": "g'",
        "д": "d",
        "е": "e",
        "ё": "yo",
        "ж": "j",
        "з": "z",
        "и": "i",
        "й": "y",
        "к": "k",
        "қ": "q",
        "л": "l",
        "м": "m",
        "н": "n",
        "о": "o",
        "ў": "o'",
        "п": "p",
        "р": "r",
        "с": "s",
        "т": "t",
        "у": "u",
        "ф": "f",
        "х": "x",
        "ҳ": "h",
        "ч": "ch",
        "ш": "sh",
        "ю": "yu",
        "я": "ya",
        "ь": "",
        "ъ": "",
    }
    def apply_case(src: str, dst: str) -> str:
        if src.isupper():
            return dst.upper()
        if src[:1].isupper():
            return dst[:1].upper() + dst[1:]
        return dst

    out = []
    for ch in t:
        lower = ch.lower()
        if lower in mapping:
            out.append(apply_case(ch, mapping[lower]))
        else:
            out.append(ch)
    return "".join(out)


def _ensure_latin_ui(page) -> None:
    page.evaluate(
        """() => {
            const langBtn = Array.from(document.querySelectorAll('button'))
                .find(b => (b.textContent || '').trim() === 'Ўзбек');
            if (langBtn) langBtn.click();
        }"""
    )
    page.wait_for_timeout(150)
    page.evaluate(
        """() => {
            const latinBtn = Array.from(document.querySelectorAll('button'))
                .find(b => (b.textContent || '').trim() === "O'zbek");
            if (latinBtn) latinBtn.click();
        }"""
    )
    page.wait_for_timeout(250)


def _ensure_cyrillic_ui(page) -> None:
    page.evaluate(
        """() => {
            const langBtn = Array.from(document.querySelectorAll('button'))
                .find(b => (b.textContent || '').trim() === "O'zbek");
            if (langBtn) langBtn.click();
        }"""
    )
    page.wait_for_timeout(150)
    page.evaluate(
        """() => {
            const cyrBtn = Array.from(document.querySelectorAll('button'))
                .find(b => (b.textContent || '').trim() === 'Ўзбек');
            if (cyrBtn) cyrBtn.click();
        }"""
    )
    page.wait_for_timeout(250)


def _load_city_name_map() -> dict[str, str]:
    global _CITY_NAME_MAP
    if _CITY_NAME_MAP is not None:
        return _CITY_NAME_MAP
    try:
        with open(CITY_NAME_MAP_PATH, "r", encoding="utf-8") as f:
            _CITY_NAME_MAP = json.load(f)
    except Exception:
        _CITY_NAME_MAP = {}
    return _CITY_NAME_MAP


def _city_label(cyrillic_name: str) -> str:
    mapping = _load_city_name_map()
    return mapping.get(cyrillic_name, cyrillic_to_latin(cyrillic_name))


def generate_city_name_map() -> dict[str, str]:
    """Generate Cyrillic -> Latin city name map from the site dropdown."""
    # Build a Cyrillic -> Latin map from the site dropdown in both languages.
    page = _get_playwright_page(TAQVIM_URL)
    if not page.url.startswith(TAQVIM_URL):
        page.goto(TAQVIM_URL, wait_until="domcontentloaded", timeout=60000)

    regions = get_regions()
    region_cyr = [r["name"] for r in regions]
    region_lat = [cyrillic_to_latin(r["name"]) for r in regions]

    def open_dropdown(candidates: list[str]) -> None:
        page.wait_for_function(
            """(names) => {
                const btns = Array.from(document.querySelectorAll('button'));
                return btns.some(b => names.includes((b.textContent || '').trim()));
            }""",
            arg=candidates,
            timeout=8000,
        )
        page.evaluate(
            """(names) => {
                const btns = Array.from(document.querySelectorAll('button'));
                const btn = btns.find(b => names.includes((b.textContent || '').trim()));
                if (btn) btn.click();
            }""",
            candidates,
        )
        page.wait_for_timeout(200)

    def read_dropdown(hints: list[str]) -> list[str]:
        return page.evaluate(
            """(hintList) => {
                const candidates = Array.from(document.querySelectorAll('ul, div'))
                    .map(el => ({
                        el,
                        buttons: Array.from(el.querySelectorAll('button')),
                        links: Array.from(el.querySelectorAll('a')),
                    }))
                    .filter(x => x.buttons.length + x.links.length > 10);
                if (!candidates.length) return [];
                const pickText = (items) => items.map(b => (b.textContent || '').trim()).filter(t => t.length > 0);
                let best = null;
                let bestScore = -1;
                for (const cand of candidates) {
                    const items = cand.buttons.length ? cand.buttons : cand.links;
                    const texts = pickText(items);
                    if (!texts.length) continue;
                    const score = hintList.filter(h => texts.some(t => t.includes(h))).length;
                    if (score > bestScore || (score === bestScore && texts.length > (best ? best.length : 0))) {
                        bestScore = score;
                        best = texts;
                    }
                }
                return best || [];
            }""",
            hints,
        )

    _ensure_cyrillic_ui(page)
    open_dropdown(region_cyr + region_lat)
    cyr_list = read_dropdown(["Тошкент", "Андижон", "Самарқанд", "Бухоро"])
    if len(cyr_list) < 10:
        open_dropdown(["Тошкент", "Toshkent"])
        cyr_list = read_dropdown(["Тошкент", "Андижон", "Самарқанд", "Бухоро"])
    _ensure_latin_ui(page)
    open_dropdown(region_lat + region_cyr)
    lat_list = read_dropdown(["Toshkent", "Andijon", "Samarqand", "Buxoro"])
    if len(lat_list) < 10:
        open_dropdown(["Toshkent", "Тошкент"])
        lat_list = read_dropdown(["Toshkent", "Andijon", "Samarqand", "Buxoro"])

    if not cyr_list or not lat_list or len(cyr_list) != len(lat_list):
        raise RuntimeError(
            f"Could not build mapping. cyr={len(cyr_list)} latin={len(lat_list)}"
        )

    mapping = {}
    for c, l in zip(cyr_list, lat_list):
        if c in {"Излаш", "Кириш", "Ўзбек"}:
            continue
        if l in {"Izlash", "Kirish", "O'zbek"}:
            continue
        mapping[c] = l
    os.makedirs(MAPS_DIR, exist_ok=True)
    with open(CITY_NAME_MAP_PATH, "w", encoding="utf-8") as f:
        json.dump(mapping, f, ensure_ascii=False, indent=2)
    return mapping


def write_language_maps(
    city_path: str = CITY_NAME_MAP_PATH,
    weekday_path: str = WEEKDAY_MAP_PATH,
    prayer_path: str = PRAYER_MAP_PATH,
) -> dict[str, str]:
    """Write city/weekday/prayer maps to islomuz_api/data/maps/."""
    os.makedirs(MAPS_DIR, exist_ok=True)
    mapping = generate_city_name_map()
    with open(weekday_path, "w", encoding="utf-8") as f:
        json.dump(WEEKDAY_CYR_TO_LATIN, f, ensure_ascii=False, indent=2)
    with open(prayer_path, "w", encoding="utf-8") as f:
        json.dump(PRAYER_CYR_TO_LATIN, f, ensure_ascii=False, indent=2)
    return mapping


def _get_playwright_page(url: str = TAQVIM_URL):
    global _PW, _BROWSER, _PAGE
    if _PAGE is not None and not _PAGE.is_closed():
        return _PAGE

    os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", PLAYWRIGHT_BROWSERS_PATH)
    _PW = sync_playwright().start()
    _BROWSER = _PW.chromium.launch(
        headless=True,
        args=[
            "--no-sandbox",
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",
            "--no-zygote",
        ],
    )
    _PAGE = _BROWSER.new_page()
    # Speed up: block heavy resources and keep a warm page for reuse.
    _PAGE.route(
        "**/*",
        lambda route, request: route.abort()
        if request.resource_type in {"image", "media", "font"}
        else route.continue_(),
    )
    _PAGE.goto(url, wait_until="domcontentloaded", timeout=60000)
    _ensure_latin_ui(_PAGE)
    return _PAGE


def close_playwright() -> None:
    """Close the shared Playwright browser/page to free resources."""
    global _PW, _BROWSER, _PAGE
    try:
        if _PAGE is not None and not _PAGE.is_closed():
            _PAGE.close()
    finally:
        _PAGE = None
    try:
        if _BROWSER is not None:
            _BROWSER.close()
    finally:
        _BROWSER = None
    try:
        if _PW is not None:
            _PW.stop()
    finally:
        _PW = None


def _select_city_and_get_html(city_name: str, url: str = TAQVIM_URL) -> str:
    region = find_region(city_name)
    if region:
        city_name = region["name"]
    city_label = _city_label(city_name)
    page = _get_playwright_page(url)

    def click_button_text(text: str) -> bool:
        return bool(
            page.evaluate(
                """(t) => {
                    const btns = Array.from(document.querySelectorAll('button'));
                    const btn = btns.find(b => (b.textContent || '').trim() === t);
                    if (btn) { btn.click(); return true; }
                    return false;
                }""",
                text,
            )
        )

    # Ensure page is at the target URL and in Latin UI.
    if not page.url.startswith(url):
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
    _ensure_latin_ui(page)

    # Open city dropdown (find a button that matches any region name)
    region_names = set()
    for r in get_regions():
        region_names.add(_city_label(r["name"]))
    buttons = page.eval_on_selector_all(
        "button",
        "els => els.map(e => (e.textContent || '').trim()).filter(t => t.length > 0)",
    )
    current_text = None
    for t in buttons:
        if t in region_names:
            current_text = t
            break
    if not current_text:
        current_text = "Toshkent"
    click_button_text(current_text)
    page.wait_for_timeout(200)

    # Select target city (by contains)
    page.evaluate(
        """(t) => {
            const btns = Array.from(document.querySelectorAll('button'));
            const btn = btns.find(b => (b.textContent || '').includes(t));
            if (btn) btn.click();
        }""",
        city_label,
    )

    # Wait for table title to include selected city
    page.wait_for_function(
        """(city) => {
            const el = document.querySelector('.taqvim-table-title');
            if (!el) return false;
            return (el.textContent || '').toLowerCase().includes(city.toLowerCase());
        }""",
        arg=city_label,
        timeout=8000,
    )
    return page.content()


def _extract_hijri_text(soup: BeautifulSoup) -> str | None:
    title = soup.select_one(".taqvim-table-title")
    if title:
        t = title.get_text(" ", strip=True)
        m = re.search(r"(Ҳижрий|Hijriy)\s*\d{3,4}", t, flags=re.IGNORECASE)
        if m:
            return m.group(0)
    return None


def _extract_hijri_meta(soup: BeautifulSoup) -> dict | None:
    title = soup.select_one(".taqvim-table-title")
    if not title:
        return None
    t = title.get_text(" ", strip=True)
    year_m = re.search(r"(Ҳижрий|Hijriy)\s*(\d{3,4})", t, flags=re.IGNORECASE)
    month_m = re.search(r"билан\s+(.+?)\s+ойи", t, flags=re.IGNORECASE)
    if not month_m:
        month_m = re.search(r"bilan\s+(.+?)\s+oyi", t, flags=re.IGNORECASE)
    if not year_m:
        return None
    return {
        "year": int(year_m.group(2)),
        "month_name": month_m.group(1) if month_m else None,
        "title": t,
    }


def _extract_gregorian_month(soup: BeautifulSoup) -> dict | None:
    title = soup.select_one(".taqvim-table-title")
    if not title:
        return None
    t = title.get_text(" ", strip=True).lower()
    # Example: "Тошкент вақти билан март ойи намоз вақтлари"
    for name, num in RU_MONTH_NAME_TO_NUM.items():
        if f" {name} " in t:
            return {"month": num, "year": date.today().year}
    # Latin: "Toshkent vaqti bilan mart oyi namoz vaqtlari"
    for name, num in LATIN_MONTH_NAME_TO_NUM.items():
        if f" {name} " in t:
            return {"month": num, "year": date.today().year}
    return None


def _cache_dir(ym: str) -> str:
    return os.path.join(CACHE_DIR, ym, "latin")


def _cache_path(kind: str, ym: str) -> str:
    return os.path.join(_cache_dir(ym), f"{kind}.json")


def _current_ym() -> str:
    return date.today().strftime("%Y-%m")


def _load_cache(path: str) -> dict | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _save_cache(path: str, payload: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _parse_table(html: str) -> dict:
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find(
        "table",
        class_=lambda c: c
        and "taqvim-table" in c
        and "taqvim-table--desktop" in c,
    )
    page_date = date.today().isoformat()
    hijri = _extract_hijri_text(soup)
    hijri_meta = _extract_hijri_meta(soup)
    greg_month = _extract_gregorian_month(soup)
    if not table:
        return {
            "headers": [],
            "rows": [],
            "hijri": hijri,
            "hijri_meta": hijri_meta,
            "date": page_date,
            "gregorian_month": greg_month,
        }

    headers: list[str] = []
    thead = table.find("thead")
    if thead:
        headers = [
            " ".join(th.get_text(" ", strip=True).split())
            for th in thead.find_all("th")
        ]

    rows: list[list[str]] = []
    tbody = table.find("tbody")
    trs = tbody.find_all("tr") if tbody else table.find_all("tr")
    for tr in trs:
        cells = [
            " ".join(td.get_text(" ", strip=True).split())
            for td in tr.find_all(["td", "th"])
        ]
        if cells and cells != headers:
            rows.append(cells)

    return {
        "headers": headers,
        "rows": rows,
        "hijri": hijri,
        "hijri_meta": hijri_meta,
        "date": page_date,
        "gregorian_month": greg_month,
    }


def _load_city_from_cache(kind: str, city_name: str) -> dict | None:
    ym = _current_ym()
    path = _cache_path(kind, ym)
    payload = _load_cache(path)
    if not payload:
        return None
    city_key = canonical_city_name(city_name)
    city = payload.get("cities", {}).get(city_key)
    if not city:
        return None
    return {
        "headers": payload.get("columns", payload.get("headers", [])),
        "rows": city.get("rows", []),
        "hijri": city.get("hijri"),
        "hijri_meta": city.get("hijri_meta"),
        "date": city.get("date"),
        "gregorian_month": city.get("gregorian_month"),
    }


def get_cached_monthly(city_name: str, kind: str = "gregorian") -> dict | None:
    return _load_city_from_cache(kind, city_name)


def _save_city_to_cache(kind: str, city_name: str, data: dict) -> None:
    ym = _current_ym()
    path = _cache_path(kind, ym)
    columns = [HEADER_MAP.get(h) or HEADER_MAP_LATIN.get(h) or h for h in data.get("headers", [])]
    payload = _load_cache(path) or {
        "ym": ym,
        "lang": "latin",
        "columns": columns,
        "cities": {},
    }
    if not payload.get("columns") and columns:
        payload["columns"] = columns
    payload["cities"][canonical_city_name(city_name)] = {
        "rows": data.get("rows", []),
        "hijri": data.get("hijri"),
        "hijri_meta": data.get("hijri_meta"),
        "date": data.get("date"),
        "gregorian_month": data.get("gregorian_month"),
    }
    _save_cache(path, payload)


def get_monthly_taqvim(city_name: str, use_cache: bool = True) -> dict:
    """Return monthly table dict with headers/rows for a city."""
    if use_cache:
        cached = _load_city_from_cache("gregorian", city_name)
        if cached:
            return cached
    html = _select_city_and_get_html(city_name)
    parsed = _parse_table(html)
    _save_city_to_cache("gregorian", city_name, parsed)
    # Returns: {"headers": [...], "rows": [...], "hijri": str|None, "date": "YYYY-MM-DD", ...}
    return parsed


def get_hijri_for_date(_: str, __: date) -> None:
    """Hijri is not fetched from the site anymore (placeholder)."""
    # Hijri is not fetched from the site anymore.
    return None


def get_day(city_name: str, target_date: date) -> dict | None:
    """Return a single day dict: {date, page_date, weekday, times}."""
    table = get_monthly_taqvim(city_name)
    rows = table.get("rows", [])
    headers = table.get("headers", [])

    # Table date format: day number only (current month).
    target = str(target_date.day)
    for row in rows:
        if row and row[0].lstrip("0") == target:
            times = {}
            for k, v in zip(headers, row):
                key = HEADER_MAP.get(k) or HEADER_MAP_LATIN.get(k) or k
                times[key] = v
            return {
                "date": {
                    "day": target_date.day,
                    "month": target_date.month,
                    "year": target_date.year,
                    "iso": target_date.isoformat(),
                },
                "page_date": table.get("date"),
                "weekday": times.get("weekday"),
                "times": {k: v for k, v in times.items() if k not in {"date_day", "weekday"}},
            }
    return None


def get_today(city_name: str) -> dict | None:
    """Return today's prayer times for a city."""
    return get_day(city_name, date.today())


def prefetch_all_monthly() -> dict:
    """Fetch and cache the current month's table for all regions."""
    ym = _current_ym()
    regions = get_regions()
    result = {
        "ym": ym,
        "lang": "latin",
        "gregorian": {"total": len(regions), "ok": 0, "failed": []},
    }
    gregorian_bundle = {"ym": ym, "lang": "latin", "columns": [], "cities": {}}
    for region in regions:
        try:
            data = get_monthly_taqvim(region["name"], use_cache=False)
            if not gregorian_bundle["columns"] and data.get("headers"):
                gregorian_bundle["columns"] = [
                    HEADER_MAP.get(h) or HEADER_MAP_LATIN.get(h) or h
                    for h in data.get("headers", [])
                ]
            gregorian_bundle["cities"][region["name"]] = {
                "rows": data.get("rows", []),
                "hijri": data.get("hijri"),
                "hijri_meta": data.get("hijri_meta"),
                "date": data.get("date"),
                "gregorian_month": data.get("gregorian_month"),
            }
            result["gregorian"]["ok"] += 1
        except Exception:
            result["gregorian"]["failed"].append(region.name)
    _save_cache(_cache_path("gregorian", ym), gregorian_bundle)
    return result


def prefetch_all_monthly_fast() -> dict:
    """Fast full-month prefetch using a single Playwright page."""
    ym = _current_ym()
    regions = get_regions()
    result = {
        "ym": ym,
        "lang": "latin",
        "gregorian": {"total": len(regions), "ok": 0, "failed": []},
    }
    gregorian_bundle = {"ym": ym, "lang": "latin", "columns": [], "cities": {}}

    os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", PLAYWRIGHT_BROWSERS_PATH)
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-dev-shm-usage",
                "--no-zygote",
            ],
        )
        page = browser.new_page()
        page.route(
            "**/*",
            lambda route, request: route.abort()
            if request.resource_type in {"image", "media", "font"}
            else route.continue_(),
        )
        page.goto(TAQVIM_URL, wait_until="domcontentloaded", timeout=60000)

        _ensure_latin_ui(page)

        def click_button_text(text: str) -> bool:
            return bool(
                page.evaluate(
                    """(t) => {
                        const btns = Array.from(document.querySelectorAll('button'));
                        const btn = btns.find(b => (b.textContent || '').trim() === t);
                        if (btn) { btn.click(); return true; }
                        return false;
                    }""",
                    text,
                )
            )

        # Use Latin names for UI selection.
        region_names = {_city_label(r["name"]) for r in regions}

        for region in regions:
            try:
                # Open city dropdown
                current_text = None
                buttons = page.eval_on_selector_all(
                    "button",
                    "els => els.map(e => (e.textContent || '').trim()).filter(t => t.length > 0)",
                )
                for t in buttons:
                    if t in region_names:
                        current_text = t
                        break
                if current_text:
                    click_button_text(current_text)
                    page.wait_for_timeout(200)

                # Select target city
                target_label = _city_label(region["name"])
                # Click by contains (more robust than exact match)
                page.evaluate(
                    """(t) => {
                        const btns = Array.from(document.querySelectorAll('button'));
                        const btn = btns.find(b => (b.textContent || '').includes(t));
                        if (btn) { btn.click(); return true; }
                        return false;
                    }""",
                    target_label,
                )
                # Wait for table title to include selected city name (latin or cyrillic)
                page.wait_for_function(
                    """(city) => {
                        const el = document.querySelector('.taqvim-table-title');
                        if (!el) return false;
                        const t = (el.textContent || '').toLowerCase();
                        return t.includes(city.toLowerCase());
                    }""",
                    arg=target_label,
                    timeout=8000,
                )

                html = page.content()
                data = _parse_table(html)
                if not gregorian_bundle["columns"] and data.get("headers"):
                    gregorian_bundle["columns"] = [
                        HEADER_MAP.get(h) or HEADER_MAP_LATIN.get(h) or h
                        for h in data.get("headers", [])
                    ]
                rows = data.get("rows", [])
                gregorian_bundle["cities"][region["name"]] = {
                    "rows": rows,
                    "hijri": data.get("hijri"),
                    "hijri_meta": data.get("hijri_meta"),
                    "date": data.get("date"),
                    "gregorian_month": data.get("gregorian_month"),
                }
                result["gregorian"]["ok"] += 1
            except Exception:
                result["gregorian"]["failed"].append(region["name"])

        browser.close()

    # Fallback: retry failures using slow path (outside Playwright context).
    if result["gregorian"]["failed"]:
        remaining = []
        for name in result["gregorian"]["failed"]:
            try:
                data = get_monthly_taqvim(name, use_cache=False)
                if not gregorian_bundle["columns"] and data.get("headers"):
                    gregorian_bundle["columns"] = [
                        HEADER_MAP.get(h) or HEADER_MAP_LATIN.get(h) or h
                        for h in data.get("headers", [])
                    ]
                rows = data.get("rows", [])
                gregorian_bundle["cities"][name] = {
                    "rows": rows,
                    "hijri": data.get("hijri"),
                    "hijri_meta": data.get("hijri_meta"),
                    "date": data.get("date"),
                    "gregorian_month": data.get("gregorian_month"),
                }
                result["gregorian"]["ok"] += 1
            except Exception:
                remaining.append(name)
        result["gregorian"]["failed"] = remaining

    _save_cache(_cache_path("gregorian", ym), gregorian_bundle)
    return result


def ensure_month_cache() -> dict:
    """Ensure current-month cache exists; prefetch if missing."""
    ym = _current_ym()
    missing = False
    if not _load_cache(_cache_path("gregorian", ym)):
        missing = True
    if missing:
        return prefetch_all_monthly()
    return {
        "ym": ym,
        "lang": "latin",
        "status": "cache-ready",
    }


def migrate_cache_compact() -> dict:
    """Migrate legacy cache format to compact format (once-off)."""
    migrated = []
    for ym in os.listdir(CACHE_DIR):
        ym_path = os.path.join(CACHE_DIR, ym)
        if not os.path.isdir(ym_path):
            continue
        for lang in os.listdir(ym_path):
            lang_path = os.path.join(ym_path, lang)
            if not os.path.isdir(lang_path):
                continue
            for kind in ["gregorian", "hijri"]:
                path = os.path.join(lang_path, f"{kind}.json")
                payload = _load_cache(path)
                if not payload or "cities" not in payload:
                    continue
                # If already compact (top-level columns), keep.
                if payload.get("columns"):
                    continue
                cities = payload.get("cities", {})
                headers = None
                compact_cities = {}
                for city, data in cities.items():
                    if not headers and isinstance(data, dict):
                        headers = data.get("headers", [])
                    compact_cities[city] = {
                        "rows": data.get("rows", []),
                        "hijri": data.get("hijri"),
                        "hijri_meta": data.get("hijri_meta"),
                        "date": data.get("date"),
                        "gregorian_month": data.get("gregorian_month"),
                    }
                columns = [
                    HEADER_MAP.get(h) or HEADER_MAP_LATIN.get(h) or h
                    for h in (headers or [])
                ]
                new_payload = {
                    "ym": payload.get("ym", ym),
                    "lang": payload.get("lang", lang),
                    "columns": columns,
                    "cities": compact_cities,
                }
                _save_cache(path, new_payload)
                migrated.append(path)
    return {"migrated": migrated}


def get_current_and_next(city_name: str) -> dict | None:
    """Return current and next prayer windows for a city."""
    day = get_today(city_name)
    if not day:
        return None

    times = day["times"]

    now = datetime.now().time()
    order = ["fajr", "sunrise", "ishraq", "dhuhr", "asr", "maghrib", "isha", "tahajjud"]
    schedule = []
    for k in order:
        v = times.get(k)
        if not isinstance(v, str):
            continue
        try:
            t = datetime.strptime(v, "%H:%M").time()
        except Exception:
            continue
        schedule.append((k, t))

    current = None
    next_item = None
    for i, (k, t) in enumerate(schedule):
        if now < t:
            next_item = {"key": k, "time": t.strftime("%H:%M")}
            prev = schedule[i - 1] if i > 0 else schedule[-1]
            current = {
                "key": prev[0],
                "start": prev[1].strftime("%H:%M"),
                "end": t.strftime("%H:%M"),
            }
            break
    if not current and schedule:
        current = {
            "key": schedule[-1][0],
            "start": schedule[-1][1].strftime("%H:%M"),
            "end": schedule[0][1].strftime("%H:%M"),
        }
        next_item = {"key": schedule[0][0], "time": schedule[0][1].strftime("%H:%M")}

    # Returns: {"times": {...}, "current": {...}|None, "next": {...}|None, "date": {...}}
    return {"times": times, "current": current, "next": next_item, "date": day.get("date")}


def time_get_day(city_name: str, target_date: date) -> dict:
    """Return timing info plus get_day() data: {seconds, data}."""
    import time

    start = time.perf_counter()
    data = get_day(city_name, target_date)
    elapsed = time.perf_counter() - start
    return {"seconds": round(elapsed, 4), "data": data}
