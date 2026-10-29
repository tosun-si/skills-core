---
name: unit-test-given-when-then
description: Generates Python unit tests following Given-When-Then convention with pytest and Pydantic validation patterns
---

# Skill: Unit Test — Given When Then

## Context

This skill generates **Python unit tests** following the **Given-When-Then** (GWT) convention. It uses `pytest` with `@pytest.mark.parametrize` for data-driven tests and `Pydantic` `ValidationError` for validation assertions. This convention is enforced across all FCO Data projects.

## Required parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `MODULE_UNDER_TEST` | The module/class being tested | `raw_data_validator.domain.sg.mobipilot.airplus.airplus_raw` |
| `CLASS_UNDER_TEST` | The class or function to test | `AirPlusRaw` |
| `TEST_SCENARIOS` | List of valid/invalid input scenarios | See examples below |
| `VALIDATION_LIB` | Validation library used | `pydantic`, `dataclasses`, `custom` |

## Naming conventions

### Test file naming

```
tests/
└── domain/
    └── <DOMAIN>/
        └── <PROJECT>/
            └── <FEATURE>/
                └── test_<feature>_<layer>.py
```

Example: `tests/domain/sg/mobipilot/airplus/test_airplus_raw.py`

### Test function naming

Test function names **must** follow the pattern:

```
test_given_<PRECONDITION>_when_<ACTION>_then_<EXPECTED_RESULT>
```

Rules:
- All lowercase with underscores
- **given**: describes the input state or precondition
- **when**: describes the action being tested
- **then**: describes the expected outcome
- Keep each section concise but descriptive

#### Examples

| Function name | Meaning |
|---------------|---------|
| `test_given_correct_airplus_raw_data_when_validate_raw_data_then_no_error` | Valid input → validation passes |
| `test_given_invalid_airplus_raw_data_when_validate_raw_data_then_error` | Invalid input → validation raises error |
| `test_given_invoice_date_mismatch_when_validate_then_raises_error` | Date mismatch → raises error |
| `test_given_empty_dataframe_when_process_then_returns_empty` | Empty input → empty output |
| `test_given_duplicate_rows_when_deduplicate_then_keeps_first` | Duplicates → keeps first occurrence |

## Test structure

### Pattern 1 — Valid input with parametrize (happy path)

```python
@pytest.mark.parametrize(
    "input_data",
    [
        # --- Case 1: <describe what this case tests> ---
        {
            "field_1": "valid_value_1",
            "field_2": "valid_value_2",
        },
        # --- Case 2: <describe what this case tests> ---
        {
            "field_1": "another_valid_value",
            "field_2": "another_valid_value",
        },
    ],
)
def test_given_correct_<feature>_data_when_validate_then_no_error(
    input_data,
):
    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result is not None
```

### Pattern 2 — Invalid input with parametrize (error path)

```python
@pytest.mark.parametrize(
    "input_data",
    [
        # --- Case 1: <describe what makes this invalid> ---
        {
            "field_1": "invalid_value",
            "field_2": "valid_value",
        },
        # --- Case 2: <describe another invalid scenario> ---
        {
            "field_1": "valid_value",
            "field_2": "invalid_value",
        },
    ],
)
def test_given_invalid_<feature>_data_when_validate_then_error(
    input_data,
):
    # WHEN / THEN
    with pytest.raises(ValidationError):
        MyModel(**input_data)
```

### Pattern 3 — Specific business rule (standalone test)

```python
def test_given_<specific_condition>_when_<action>_then_<expected>():
    """Docstring explaining the business rule being tested."""
    # GIVEN
    input_data = {
        "field_1": "specific_value",
        "field_2": "another_value",
    }

    # WHEN
    result = MyModel(**input_data)

    # THEN
    assert result is not None
    assert result.computed_field == expected_value
```

### Pattern 4 — Error message assertion

```python
def test_given_<condition>_when_<action>_then_raises_error_with_message():
    """Test that a specific error message is raised."""
    # WHEN / THEN
    with pytest.raises(ValidationError) as exc:
        MyModel(
            field_1="invalid_value",
            field_2="valid_value",
        )
    assert "does not match" in str(exc.value)
```

### Pattern 5 — Edge case / format conversion

```python
def test_given_<edge_case>_when_<action>_then_<expected>():
    """Test edge case: <describe the edge case>."""
    # GIVEN
    model = MyModel(
        field_1="edge_case_value",  # e.g. Excel serial number instead of date
        field_2="normal_value",
    )

    # THEN
    assert model is not None
```

## Going further (load only when needed)

- **Advanced parametrize patterns** (explicit ids, expected error messages,
  `marks`, stacked parametrize, fixture injection, mapping tests) →
  [`references/advanced-parametrize-patterns.md`](references/advanced-parametrize-patterns.md).
  Read it when a test needs more than the five patterns above.
- **A complete reference test file** →
  [`references/reference-test-file.md`](references/reference-test-file.md).
  Read it when scaffolding the first test file of a project.

## Inline comments convention

### Section markers in `@pytest.mark.parametrize`

Each test case inside `parametrize` must have a comment header:

```python
# --- Case N: <short description of what this case tests> ---
```

### GWT markers in test body

Use inline comments to separate Given/When/Then sections:

```python
# GIVEN       → setup phase (optional if parametrized)
# WHEN        → action under test
# THEN        → assertions
# WHEN / THEN → combined when action and assertion are in one statement (e.g. pytest.raises)
```

## Mandatory conventions

- **Always** use the `test_given_<X>_when_<Y>_then_<Z>` naming pattern
- **Always** use `@pytest.mark.parametrize` for data-driven tests with 2+ cases
- **Always** add `# --- Case N: ... ---` comments in parametrized data
- **Always** add `# GIVEN`, `# WHEN`, `# THEN` section markers in the test body
- **Always** test both valid (happy path) and invalid (error path) scenarios
- **Always** write test descriptions and comments in **English**
- **Always** use `pytest.raises(ValidationError)` for Pydantic validation errors
- **Always** assert error messages with `in str(exc.value)` when testing specific error messages
- **Never** use `unittest.TestCase` — always use pytest function-based tests
- **Never** use mocks when you can test with real data (integration-first mindset)
- **Never** write tests without the GWT naming convention
- Prefer **explicit test data** over fixtures/factories for readability
- One **assert per test** (or one logical assertion group)
- Group parametrized cases by **validation theme** (dates, numerics, required fields, etc.)

## Test categories to cover

For any Pydantic model or data validation class, generate tests for:

| Category | Test name pattern | Description |
|----------|-------------------|-------------|
| Happy path | `test_given_correct_<feature>_data_when_validate_then_no_error` | All fields valid |
| Invalid format | `test_given_invalid_<feature>_data_when_validate_then_error` | Wrong format/type |
| Missing required | `test_given_missing_required_field_when_validate_then_error` | Required field empty/None |
| Business rule | `test_given_<rule_condition>_when_validate_then_<outcome>` | Domain-specific validation |
| Edge case | `test_given_<edge_case>_when_<action>_then_<expected>` | Boundary values, format conversions |
| Error message | `test_given_<condition>_when_validate_then_raises_error_with_message` | Specific error message content |

## pyproject.toml test configuration

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = "test_*.py"
markers = [
    "integration: marks tests as integration tests",
    "slow: marks tests as slow",
]

[tool.coverage.run]
source = ["src"]
omit = ["tests/*"]

[tool.coverage.report]
fail_under = 80
show_missing = true
```

## References

- [pytest documentation](https://docs.pytest.org/)
- [Pydantic validation](https://docs.pydantic.dev/latest/concepts/validators/)
- [Given-When-Then convention](https://martinfowler.com/bliki/GivenWhenThen.html)
- Reference implementation: `raw-data-validator` — `test_airplus_raw.py`
