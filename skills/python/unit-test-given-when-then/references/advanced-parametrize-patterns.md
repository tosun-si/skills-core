# Advanced parametrize patterns

Loaded on demand by the `unit-test-given-when-then` skill — patterns 6 to 11.

### Pattern 6 — Multiple parameters with explicit IDs

Use `pytest.param` with `id=` for readable test output instead of `input_data0`, `input_data1`, etc.

```python
@pytest.mark.parametrize(
    "input_data, expected_field_value",
    [
        pytest.param(
            {
                "filename": "Dettes_202302_20230315120000.csv",
                "insert_date": "2025-01-19 09:29:46.608638",
                "periode": "202302",
                "montant_dette": "1234.56",
                "devise": "EUR",
            },
            "202302",
            id="standard_periode_yyyymm",
        ),
        pytest.param(
            {
                "filename": "Dettes_202401_20240201100000.csv",
                "insert_date": "2024-02-01 10:00:00",
                "periode": "202401",
                "montant_dette": "0",
                "devise": "USD",
            },
            "202401",
            id="january_2024_usd",
        ),
    ],
)
def test_given_correct_data_when_validate_then_periode_matches(
    input_data, expected_field_value
):
    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result.periode == expected_field_value
```

### Pattern 7 — Parametrize with expected error message

Test multiple invalid scenarios and verify the specific error message for each.

```python
@pytest.mark.parametrize(
    "input_data, expected_error_fragment",
    [
        pytest.param(
            {"periode": "2023-02", "montant_dette": "100", "devise": "EUR"},
            "YYYYMM format",
            id="invalid_periode_with_dash",
        ),
        pytest.param(
            {"periode": "202302", "montant_dette": "abc", "devise": "EUR"},
            "valid number",
            id="non_numeric_montant",
        ),
        pytest.param(
            {"periode": "202302", "montant_dette": "100", "devise": "euros"},
            "ISO 4217",
            id="invalid_devise_lowercase",
        ),
    ],
)
def test_given_invalid_field_when_validate_then_error_contains_message(
    input_data, expected_error_fragment
):
    # WHEN / THEN
    with pytest.raises(ValidationError) as exc:
        MyModel(**input_data)
    assert expected_error_fragment in str(exc.value)
```

### Pattern 8 — Parametrize with `marks` for conditional tests

Use `pytest.mark.xfail` or `pytest.mark.skip` on specific cases inside parametrize.

```python
@pytest.mark.parametrize(
    "input_data",
    [
        pytest.param(
            {"periode": "202302", "montant_dette": "100.0", "devise": "EUR"},
            id="standard_case",
        ),
        pytest.param(
            {"periode": "202302", "montant_dette": "1e5", "devise": "EUR"},
            id="scientific_notation",
            marks=pytest.mark.xfail(reason="Scientific notation not yet supported"),
        ),
        pytest.param(
            {"periode": "202302", "montant_dette": "100 000", "devise": "EUR"},
            id="space_thousands_separator",
            marks=pytest.mark.skip(reason="Pending business rule clarification"),
        ),
    ],
)
def test_given_edge_case_formats_when_validate_then_expected_behavior(input_data):
    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result is not None
```

### Pattern 9 — Stacked parametrize (cartesian product)

Use multiple `@pytest.mark.parametrize` decorators to test all combinations.

```python
@pytest.mark.parametrize("devise", ["EUR", "USD", "GBP"])
@pytest.mark.parametrize("montant", ["100.0", "0", "-50.25", "1234,56"])
def test_given_valid_montant_and_devise_when_validate_then_no_error(
    montant, devise
):
    # GIVEN
    input_data = {
        "filename": "Dettes_202302_20230315120000.csv",
        "insert_date": "2025-01-19 09:29:46.608638",
        "periode": "202302",
        "unite_operationnelle": "OSA_BU01",
        "montant_dette": montant,
        "devise": devise,
    }

    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result is not None
    assert result.devise == devise
```

### Pattern 10 — Parametrize with fixture injection

Combine parametrize with fixtures for shared setup.

```python
@pytest.fixture
def base_valid_input():
    """Shared base input for all test cases."""
    return {
        "filename": "Dettes_202302_20230315120000.csv",
        "insert_date": "2025-01-19 09:29:46.608638",
        "periode": "202302",
        "unite_operationnelle": "OSA_BU01",
        "montant_dette": "100.0",
        "devise": "EUR",
    }


@pytest.mark.parametrize(
    "field_override, expected_error",
    [
        pytest.param({"periode": "toto"}, "YYYYMM format", id="invalid_periode"),
        pytest.param({"montant_dette": "abc"}, "valid number", id="invalid_montant"),
        pytest.param({"devise": "xx"}, "ISO 4217", id="invalid_devise"),
    ],
)
def test_given_one_invalid_field_when_validate_then_specific_error(
    base_valid_input, field_override, expected_error
):
    # GIVEN
    input_data = {**base_valid_input, **field_override}

    # WHEN / THEN
    with pytest.raises(ValidationError) as exc:
        MyModel(**input_data)
    assert expected_error in str(exc.value)
```

### Pattern 11 — Parametrize for transformation / mapping tests

Test that input values are correctly transformed to expected output.

```python
@pytest.mark.parametrize(
    "raw_value, expected_normalized",
    [
        pytest.param("1234,56", 1234.56, id="comma_to_dot"),
        pytest.param("1234.56", 1234.56, id="dot_unchanged"),
        pytest.param("0", 0.0, id="zero"),
        pytest.param("-100,50", -100.50, id="negative_comma"),
        pytest.param("1 234,56", 1234.56, id="space_thousands_comma"),
    ],
)
def test_given_raw_montant_when_normalize_then_returns_float(
    raw_value, expected_normalized
):
    # WHEN
    result = normalize_montant(raw_value)

    # THEN
    assert result == pytest.approx(expected_normalized)
```
