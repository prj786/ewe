#!/usr/bin/env python3
"""eds-query.py — dump evolution-data-server data as JSON for the Quickshell UI.

Usage:
    eds-query.py events [DAYS]   → {"events": [{summary,start,end,allDay,calendar}]}
    eds-query.py contacts        → {"contacts": [{name,emails,phones}]}

EDS is an optional dependency (accounts come from GNOME Online Accounts and
auto-register as EDS sources). When EDS or its GObject-introspection data is
missing, this prints {"error": "..."} on stdout and exits 0 — the shell shows
the degraded "install …" state instead of crashing. Every per-source and
per-item step is wrapped defensively for the same reason.
"""

import datetime
import json
import sys


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


try:
    import gi
    gi.require_version("EDataServer", "1.2")
    from gi.repository import EDataServer
except Exception as e:  # noqa: BLE001 — any import failure means "not available"
    out({"error": f"evolution-data-server not available: {e}"})


def cmd_events(days: int):
    try:
        gi.require_version("ECal", "2.0")
        gi.require_version("ICalGLib", "3.0")
        from gi.repository import ECal  # noqa: PLC0415
    except Exception as e:
        out({"error": f"ECal introspection missing: {e}"})

    try:
        registry = EDataServer.SourceRegistry.new_sync(None)
    except Exception as e:
        out({"error": f"EDS source registry unreachable: {e}"})

    start = datetime.datetime.now(datetime.timezone.utc)
    end = start + datetime.timedelta(days=days)
    fmt = "%Y%m%dT%H%M%SZ"
    sexp = (
        f'(occur-in-time-range? (make-time "{start.strftime(fmt)}")'
        f' (make-time "{end.strftime(fmt)}"))'
    )

    def iso(prop):
        try:
            t = prop.get_value() if prop else None
            if t is None:
                return ""
            return "%04d-%02d-%02dT%02d:%02d:%02d" % (
                t.get_year(), t.get_month(), t.get_day(),
                t.get_hour(), t.get_minute(), t.get_second(),
            )
        except Exception:
            return ""

    events = []
    for src in registry.list_enabled(EDataServer.SOURCE_EXTENSION_CALENDAR):
        try:
            client = ECal.Client.connect_sync(src, ECal.ClientSourceType.EVENTS, 5, None)
            res = client.get_object_list_as_comps_sync(sexp, None)
        except Exception:
            continue
        comps = res[1] if isinstance(res, tuple) else res
        for comp in comps or []:
            try:
                s = comp.get_summary()
                summary = s.get_value() if s else "(no title)"
                dtstart = comp.get_dtstart()
                allday = False
                try:
                    t0 = dtstart.get_value() if dtstart else None
                    allday = bool(t0 is not None and t0.is_date())
                except Exception:
                    pass
                events.append({
                    "summary": summary or "(no title)",
                    "start": iso(dtstart),
                    "end": iso(comp.get_dtend()),
                    "allDay": allday,
                    "calendar": src.get_display_name() or "",
                })
            except Exception:
                continue
    events.sort(key=lambda e: e["start"])
    out({"events": events})


def cmd_contacts():
    try:
        gi.require_version("EBook", "1.2")
        gi.require_version("EBookContacts", "1.2")
        from gi.repository import EBook, EBookContacts  # noqa: PLC0415
    except Exception as e:
        out({"error": f"EBook introspection missing: {e}"})

    try:
        registry = EDataServer.SourceRegistry.new_sync(None)
    except Exception as e:
        out({"error": f"EDS source registry unreachable: {e}"})

    def attr_values(contact, field):
        try:
            return [a.get_value() for a in (contact.get_attributes(field) or []) if a.get_value()]
        except Exception:
            return []

    contacts, seen = [], set()
    for src in registry.list_enabled(EDataServer.SOURCE_EXTENSION_ADDRESS_BOOK):
        try:
            client = EBook.BookClient.connect_sync(src, 5, None)
            query = EBookContacts.BookQuery.any_field_contains("").to_string()
            res = client.get_contacts_sync(query, None)
        except Exception:
            continue
        got = res[1] if isinstance(res, tuple) else res
        for c in got or []:
            try:
                name = c.get_property("full-name") or c.get_property("file-as") or ""
                emails = attr_values(c, EBookContacts.ContactField.EMAIL)
                phones = attr_values(c, EBookContacts.ContactField.TEL)
                if not name and not emails:
                    continue
                key = (name, tuple(sorted(emails)))
                if key in seen:
                    continue
                seen.add(key)
                contacts.append({
                    "name": name or emails[0],
                    "emails": emails,
                    "phones": phones,
                })
            except Exception:
                continue
    contacts.sort(key=lambda c: c["name"].lower())
    out({"contacts": contacts})


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "events"
    if cmd == "contacts":
        cmd_contacts()
    else:
        try:
            days = int(sys.argv[2]) if len(sys.argv) > 2 else 14
        except ValueError:
            days = 14
        cmd_events(days)
