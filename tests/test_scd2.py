"""SCD Type 2 dimension correctness tests — require a live running pipeline."""
import pytest


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_customer_update_creates_new_scd2_record():
    """Update a customer and verify dim_customer has two rows with valid_from/valid_to."""
    pass


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_previous_scd2_record_is_closed():
    """After update, verify previous record has is_active=FALSE and valid_to set."""
    pass


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_current_scd2_record_is_active():
    """After update, verify latest record has is_active=TRUE and valid_to=9999."""
    pass


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_multiple_updates_create_history():
    """Update a customer 3 times and verify 3 historical records in dim_customer."""
    pass


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_fact_invoice_resolves_correct_surrogate_key():
    """Verify fct_invoice joins to the dim_customer record active at invoice time."""
    pass


@pytest.mark.skip(reason="Requires live pipeline with data flowing through CQs")
def test_dim_track_denormalized_fields():
    """Verify dim_track includes album_title, artist_name, genre_name, media_type_name."""
    pass
