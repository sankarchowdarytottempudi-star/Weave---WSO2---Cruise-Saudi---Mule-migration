"""Owner-approved direct scope (2026-11-16): source code AND agency name, exact after trim+casefold."""
import pytest

from app.services.rule_engine import is_direct

IN_SCOPE_SOURCES = ["INT-ASSC", "INT-CON", "NEWINT-CON", "MOBAPP", "WHATSAPP", "IN HOUSE"]
IN_SCOPE_AGENCIES = ["AROYA CRUISES MAIN OFFICE", "AROYA CRUISES MAIN OFFICE USD", "AROYA CRUISES MAIN OFFICE EUR",
                     "AROYA CRUISES MAIN OFFICE GBP", "FUTURE CRUISES", "RIYADH SEASON", "WHATSAPP"]


@pytest.mark.parametrize("source", IN_SCOPE_SOURCES)
@pytest.mark.parametrize("agency", IN_SCOPE_AGENCIES)
def test_in_scope_every_combination(settings, source, agency):
    assert is_direct(source, agency, "SEAWARE", settings)


@pytest.mark.parametrize("source,agency", [("  mobapp ", "aroya cruises main office"),
                                           ("In  House", " Riyadh Season "), ("whatsapp", "WhatsApp")])
def test_trim_and_casefold(settings, source, agency):
    assert is_direct(source, agency, "SEAWARE", settings)


@pytest.mark.parametrize("source", ["INT-AGENT", "WEB", "CRM_DIRECT", "MOBAPP2", "", None])
def test_out_of_scope_source(settings, source):
    assert not is_direct(source, "AROYA CRUISES MAIN OFFICE", "SEAWARE", settings)


def test_int_agent_is_out_even_with_aroya_agency(settings):
    assert not is_direct("INT-AGENT", "AROYA CRUISES MAIN OFFICE", "SEAWARE", settings)


@pytest.mark.parametrize("agency", ["SOME TRAVEL AGENCY", "AROYA", "AROYA CRUISES", "AROYA CRUISES MAIN OFFICE SAR",
                                    "", None])
def test_direct_source_with_non_aroya_agency_is_out(settings, agency):
    assert not is_direct("MOBAPP", agency, "SEAWARE", settings)


def test_empty_agency_is_a_config_switch(settings):
    import dataclasses
    assert not is_direct("MOBAPP", "", "SEAWARE", settings) and not is_direct("MOBAPP", None, "SEAWARE", settings)
    s = dataclasses.replace(settings, accept_empty_agency=True)
    assert is_direct("MOBAPP", "  ", "SEAWARE", s) and not is_direct("INT-AGENT", None, "SEAWARE", s)
    assert not is_direct("MOBAPP", "SOME TRAVEL AGENCY", "SEAWARE", s)


def test_aroya_main_office_sar_is_out_until_added(settings):
    import dataclasses
    assert not is_direct("MOBAPP", "AROYA MAIN OFFICE SAR", "SEAWARE", settings)
    s = dataclasses.replace(settings, direct_agency_names=settings.direct_agency_names + ("AROYA MAIN OFFICE SAR",))
    assert is_direct("MOBAPP", "aroya main office sar", "SEAWARE", s)


def test_lists_are_configuration(settings):
    import dataclasses
    s = dataclasses.replace(settings, direct_source_codes=("MOBAPP",), direct_agency_names=("X",))
    assert is_direct("MOBAPP", "x", "SEAWARE", s) and not is_direct("INT-CON", "x", "SEAWARE", s)
