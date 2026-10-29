---
name: python-hexagonal-clean-archi
description: Conventions for structuring a Python service with hexagonal architecture (ports & adapters) and clean-architecture layering — domain / application / infrastructure, one-way dependency rule, single composition root for DI, *UseCase classes for use cases, fake repositories in conftest for tests, SQL-first Alembic migrations. Trigger when initializing a new Python service that needs business-logic separation, adding a new use case / port / adapter to an existing such project, reviewing layer boundaries, or deciding between a manual composition root and a DI library (dependency-injector / wireup / lagom). Framework-agnostic but examples use FastAPI + SQLAlchemy + asyncpg. For CLIs, SDKs, MCP servers and open-source tool cores, use python-hexagonal-flat instead.
---

# Python hexagonal + clean architecture

A pragmatic, batteries-included starter pattern for Python services that need to keep business logic separate from delivery and persistence concerns. Optimize for: testability without mocks, swappable adapters, single wiring point, no magic.

## The layer model

Three layers with a strict one-way dependency rule: `infrastructure → application → domain`.

| Layer | What it contains | Forbidden imports |
|---|---|---|
| **domain/** | Pure business model: entities/aggregates (dataclasses with `__post_init__` validation), value objects, domain exceptions. Optionally domain services and `domain/ports/` when the domain itself depends on an abstraction (e.g. `ClockProvider`). | Anything from `application/` or `infrastructure/`. No FastAPI, no SQLAlchemy, no asyncpg, no Pydantic. |
| **application/** | Use cases (one class per operation), DTOs (frozen dataclasses — Command in, View out), `application/ports/` (outbound interfaces — repositories, message publishers, external clients). | Anything from `infrastructure/`. Application depends only on its own ports and on domain. |
| **infrastructure/** | Adapters that implement application ports + delivery layer + wiring. Concrete repositories, HTTP routers, Pydantic schemas, error handlers, config, the composition root. | Nothing — this is the outermost layer. |

**Rule of thumb**: if removing the framework (FastAPI, SQLAlchemy) would break a `domain/` or `application/` file, the architecture is broken. They must compile and unit-test without any of it.

## Directory layout

```
<service_pkg>/                        ← single top-level Python package (no src/ layout needed)
├── __init__.py                       ← module docstring naming the service
├── domain/
│   ├── __init__.py
│   ├── models/                       ← one file per aggregate root
│   │   ├── __init__.py
│   │   └── <entity>.py
│   ├── exceptions.py                 ← DomainError + concrete subclasses
│   └── ports/                        ← OPTIONAL: only when the domain itself depends on a port
├── application/
│   ├── __init__.py
│   ├── dto/                          ← <entity>_dto.py: <Verb><Entity>Command + <Entity>View
│   ├── ports/                        ← <entity>_repository.py: ABCs, one per outbound dependency
│   └── use_cases/                    ← <verb>_<entity>_use_case.py: one *UseCase class each
└── infrastructure/
    ├── __init__.py
    ├── adapters/
    │   ├── http/                     ← FastAPI routers, Pydantic schemas, error handlers, dependencies
    │   │   ├── routers/              ← one file per OpenAPI tag group
    │   │   ├── schemas.py
    │   │   ├── error_handlers.py
    │   │   └── dependencies.py
    │   └── persistence/              ← SQLAlchemy/asyncpg adapter implementing application/ports
    │       └── sqlalchemy_<entity>_repository.py
    ├── config/
    │   └── settings.py               ← pydantic-settings, env-prefixed (e.g. API_REGISTRY_)
    ├── composition_root.py           ← single wiring point — see DI section
    └── main.py                       ← create_app() + lifespan

tests/
├── unit/
│   ├── domain/
│   │   └── test_<entity>.py          ← class Test<Entity>: with G/W/T methods
│   └── application/
│       ├── conftest.py               ← Fake*Repository fakes implementing the same ports
│       └── test_<verb>_<entity>_use_case.py
└── integration/
    ├── conftest.py                   ← real DB via testcontainers, real ASGI client
    └── test_http_routes.py
```

**One file per aggregate, one file per use case, one file per port.** Don't bundle. The slight directory bloat pays for itself in PR diff clarity.

## Naming conventions

| Concept | Pattern | Example |
|---|---|---|
| Use case class | `<Verb><Entity>UseCase` | `RegisterApiEntryUseCase` |
| Use case file | `<verb>_<entity>_use_case.py` | `register_api_entry_use_case.py` |
| Port file | `<entity>_repository.py` | `api_entry_repository.py` |
| Port class (ABC) | `<Entity>Repository` | `ApiEntryRepository` |
| Repository adapter | `<Tech><Entity>Repository` | `SqlAlchemyApiEntryRepository` |
| Command DTO | `<Verb><Entity>Command` | `RegisterApiEntryCommand` |
| View DTO | `<Entity>View` | `ApiEntryView` |
| Domain exception | `<Concept><State>Error` | `ApiEntryAlreadyExistsError` |
| Composition root | `CompositionRoot` (not `Container`, not `Registry`) | — |

The `UseCase` suffix is non-negotiable — it disambiguates from values (`GetApiEntry` reads as a verb-phrase variable; `GetApiEntryUseCase` reads as the class). Folder context is not enough.

## Where to place a port

- **Default: `application/ports/`** — repositories, message publishers, external service clients. Only use cases need them.
- **`domain/ports/` (create the folder when needed)** — only when an entity, aggregate, or domain service references the abstraction *directly* (e.g. `PasswordHasher` called inside `User.change_password()`, `ClockProvider` injected into a domain service). When in doubt, start in `application/ports/` and move down later.

## Composition root + DI

A single class in `infrastructure/composition_root.py` wires everything:

```python
class CompositionRoot:
    """Single wiring point. Binds concrete adapters to their ports and exposes
    use cases for injection via FastAPI's Depends. Swap any adapter here and
    application/domain code remains unchanged."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._database = Database(settings.postgres_dsn)
        self._api_entry_repo = SqlAlchemyApiEntryRepository(self._database.session_factory)

    @property
    def register_api_entry_use_case(self) -> RegisterApiEntryUseCase:
        return RegisterApiEntryUseCase(self._api_entry_repo)

    # ... one property per use case
```

FastAPI integration via a thin `dependencies.py`:

```python
def _composition_root() -> CompositionRoot:
    return get_composition_root()  # @lru_cache-d module-level helper

CompositionRootDep = Annotated[CompositionRoot, Depends(_composition_root)]

def register_api_entry_use_case(root: CompositionRootDep) -> RegisterApiEntryUseCase:
    return root.register_api_entry_use_case
```

Then routers use the use case via `Annotated[RegisterApiEntryUseCase, Depends(register_api_entry_use_case)]` and never import the composition root, the adapter, or the session factory.

### Why a manual CompositionRoot (not a DI library) by default

- **Zero deps, fully typed, no magic.** mypy/pyright/ty see real classes and real method signatures end-to-end.
- **One file to read** to understand the whole object graph.
- **Trivially refactorable** — `CompositionRoot.__init__` is just constructor calls.
- **Sufficient up to ~15 services with non-trivial init order.** Past that, lifecycle management (DB pools, gRPC channels, Kafka consumers) starts justifying a real container.

### When to swap in a DI library

Reach for one **only** when you have a concrete reason — not preemptively. Triggers:

1. **15+ services** with non-trivial init order. Manual wiring becomes a 200-line file with subtle ordering bugs.
2. **Real resource lifecycle**: DB pool startup/shutdown, gRPC channels, message-broker consumers — anything with `init` + `cleanup` hooks the lifespan handler must call.
3. **Multi-environment wiring** that diverges meaningfully (different adapters for dev vs prd that aren't a `Settings` flag away).
4. **Request-scoped dependencies** that don't fit FastAPI's `Depends` model.

**Pick (in this order, by 2026):**

| Library | Use when |
|---|---|
| **`wireup`** | New projects. Type-safe, decorator-based, async-native, smallest mental tax. |
| **`dependency-injector`** | Biggest ecosystem, mature `Resource` providers, most copy-pasteable examples. Bring `Provide[...]` is string-ish — type checkers strain. |
| **`lagom`** | Type-purity above all. Smaller community but excellent typing. |
| **`punq`** | Minimal, ~150 LOC of source. When the library itself must be auditable. |

The hexagonal layout means the migration is cheap: rewrite `composition_root.py`, leave `domain/` and `application/` untouched. No big-bang refactor required.

## DTOs (Commands and Views)

Frozen dataclasses, never Pydantic. Pydantic stays in `infrastructure/adapters/http/schemas.py` for HTTP wire-format only.

```python
# application/dto/api_entry_dto.py
@dataclass(frozen=True, slots=True)
class RegisterApiEntryCommand:
    name: str
    version: str
    base_url: str
    owner: str
    description: str | None = None
    tags: list[str] = field(default_factory=list)

@dataclass(frozen=True, slots=True)
class ApiEntryView:
    id: UUID
    name: str
    # ... mirror of the entity, immutable

    @classmethod
    def from_entity(cls, entry: ApiEntry) -> ApiEntryView:
        return cls(id=entry.id, name=entry.name, ...)
```

Commands are validated at construction time in the use case body if needed. Views are the only thing use cases return — never expose domain entities to the HTTP layer directly.

## Domain errors → HTTP

All business rule violations raise a `DomainError` subclass. The HTTP adapter maps each concrete type to a status code via a single dict:

```python
# infrastructure/adapters/http/error_handlers.py
EXCEPTION_STATUS_MAP: dict[type[DomainError], int] = {
    ApiEntryNotFoundError: 404,
    ApiEntryAlreadyExistsError: 409,
    # ... one row per concrete domain error
}

def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def _domain_error(_: Request, exc: DomainError) -> JSONResponse:
        status_code = EXCEPTION_STATUS_MAP.get(type(exc), 400)
        return JSONResponse(
            status_code=status_code,
            content={"title": type(exc).__name__, "detail": str(exc), "status": status_code},
        )
```

Adding a new domain error = (1) subclass in `domain/exceptions.py`, (2) one row in `EXCEPTION_STATUS_MAP`. No router-level try/except.

## SQL-first Alembic migrations

Schema definitions are plain `.sql` files; Alembic is just the runner.

```
migrations/versions/
├── 0001_create_api_entries.py       ← shim: calls op.execute(.up.sql / .down.sql)
├── 0001_create_api_entries.up.sql   ← CREATE TABLE ... (the canonical schema)
└── 0001_create_api_entries.down.sql ← DROP TABLE ...
```

The `.py` shim is auto-generated from a customized `script.py.mako` that reads the sibling `.sql` files at apply time. `env.py` has `target_metadata = None` so `--autogenerate` is deliberately disabled — schema changes are authored as SQL, not as Python model diffs.

In `tables.py` next to the adapter, keep SQLAlchemy `Table` objects that *mirror* the SQL schema for query construction only. They are not the source of truth; the `.up.sql` files are.

## Test conventions

**Unit tests** use **fake repositories** defined in `conftest.py`, never the production adapter:

```python
# tests/unit/application/conftest.py
class FakeApiEntryRepository(ApiEntryRepository):
    def __init__(self) -> None:
        self._store: dict[UUID, ApiEntry] = {}

    async def add(self, entry: ApiEntry) -> None:
        if any(e.matches(entry.name, entry.version) for e in self._store.values()):
            raise ApiEntryAlreadyExistsError(entry.name, entry.version)
        self._store[entry.id] = entry

    # ... implement every abstract method, raise the same domain exceptions as the real adapter

@pytest.fixture
def api_entry_repository() -> FakeApiEntryRepository:
    return FakeApiEntryRepository()
```

**Method names + body** follow Given/When/Then:

```python
class TestRegisterApiEntryUseCase:
    async def test_given_existing_entry_when_registering_duplicate_then_raises_conflict(
        self,
        api_entry_repository: FakeApiEntryRepository,
        sample_command: RegisterApiEntryCommand,
    ) -> None:
        # given
        use_case = RegisterApiEntryUseCase(api_entry_repository)
        await use_case.execute(sample_command)

        # when / then
        with pytest.raises(ApiEntryAlreadyExistsError):
            await use_case.execute(sample_command)
```

Rules:
- One `Test<Unit>` class per unit. No `__init__` (pytest skips classes with one).
- `test_given_<context>_when_<action>_then_<outcome>` for method names.
- `# given` / `# when` / `# then` separate the body. Collapse to `# when / then` when the action *is* the assertion.
- One behavior per test. If the name needs `_and_`, split it.
- Parametrize negative cases (one test, many invalid inputs).

**Integration tests** use a real Postgres via `testcontainers`, the real composition root (with `get_composition_root.cache_clear()` between tests), and `httpx.ASGITransport` for the HTTP layer. Truncate tables between tests via a `clean_<bounded_context>` fixture — don't drop and re-apply migrations per test.

## Anti-patterns to reject in review

| Don't | Why |
|---|---|
| Import from `infrastructure` inside `domain/` or `application/` | Breaks the dependency rule. The whole architecture exists to prevent this. |
| Use the production SQLAlchemy adapter in a unit test | Slow, brittle, defeats the point of ports. Use the fake repository. |
| Return a domain entity from a router | Couples HTTP wire format to the domain model. Always return a View DTO mapped from the entity. |
| Put business logic in a router function | Routers translate HTTP ↔ Command/View only. If there's an `if`, it probably belongs in a use case. |
| `raise Exception(...)` instead of a typed `DomainError` | Callers can't catch it specifically; the status-code mapping fails over to 400 or worse. |
| Run `alembic revision --autogenerate` | SQL-first — autogenerate is disabled. The `.up.sql` file is the source of truth. |
| Reach for a DI library before pain is real | The hand-rolled `CompositionRoot` covers ~15 services. Migration later is one file. Don't pre-optimize. |
| Import `Pydantic` in `application/` or `domain/` | Pydantic is wire-format machinery — stays in `infrastructure/adapters/http/schemas.py`. |

## Cross-references

- For CLIs, SDKs, MCP servers and open-source cores without their own database, see the **`python-hexagonal-flat`** skill: same ports and adapters, no layers, functions instead of `*UseCase` classes.
- For Python venv + uv + direnv setup, see the **`python-uv-direnv`** skill.
- For multi-stage Dockerfiles with uv, see the **`python-docker-multistage`** skill.
