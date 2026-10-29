# Reference test file

Loaded on demand by the `unit-test-given-when-then` skill: a complete file showing the conventions end to end.

```python
import pytest
from pydantic import ValidationError

from my_project.domain.feature.my_model import MyModel


@pytest.mark.parametrize(
    "input_data",
    [
        # --- Case 1: standard valid input ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "19/01/2025",
            "numeric_field": "100.0",
            "integer_field": "2",
        },
        # --- Case 2: decimal with dot separator ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "19/01/2025",
            "numeric_field": "250.75",
            "integer_field": "3",
        },
        # --- Case 3: decimal with comma separator ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "19/01/2025",
            "numeric_field": "99,99",
            "integer_field": "1",
        },
    ],
)
def test_given_correct_data_when_validate_then_no_error(input_data):
    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result is not None


@pytest.mark.parametrize(
    "input_data",
    [
        # --- Case 1: invalid date strings ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "toto",
            "numeric_field": "100.0",
            "integer_field": "2",
        },
        # --- Case 2: invalid numeric field ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "19/01/2025",
            "numeric_field": "abc",
            "integer_field": "2",
        },
        # --- Case 3: empty required field ---
        {
            "filename": "report_202501_20250103.csv",
            "insert_date": "2025-01-19 09:29:46.608638",
            "date_field": "19/01/2025",
            "numeric_field": "",
            "integer_field": "",
        },
    ],
)
def test_given_invalid_data_when_validate_then_error(input_data):
    # WHEN / THEN
    with pytest.raises(ValidationError):
        MyModel(**input_data)


def test_given_date_matches_filename_period_when_validate_then_no_error():
    """Test that date_field matches the business period from filename."""
    # GIVEN
    model = MyModel(
        filename="report_202501_20250103.csv",
        insert_date="2025-01-19 09:29:46.608638",
        date_field="19/01/2025",
        numeric_field="100.0",
        integer_field="2",
    )

    # THEN
    assert model is not None


def test_given_date_mismatch_with_filename_when_validate_then_raises_error():
    """Test that mismatched date raises error."""
    # WHEN / THEN
    with pytest.raises(ValidationError) as exc:
        MyModel(
            filename="report_202501_20250103.csv",
            insert_date="2025-01-19 09:29:46.608638",
            date_field="19/02/2025",  # February does NOT match 202501
            numeric_field="100.0",
            integer_field="2",
        )
    assert "does not match" in str(exc.value)
```
