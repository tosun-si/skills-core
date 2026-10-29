---
name: python-hexagonal-flat
description: Flat hexagonal architecture (ports & adapters) for Python tech products — CLIs, SDKs, MCP servers and open-source cores that a SaaS later builds on. One package with core/ (pure rules), ports.py (Protocols), service.py (one function per operation, ports as keyword arguments), adapters/, wiring.py (lazy adapters), thin entrypoints (cli.py, mcp.py), structural fakes in tests. Trigger when initializing such a tool, adding an operation, port, adapter or entrypoint to one, or deciding between this flat layout and the layered domain/application/infrastructure one. For HTTP services with a database, use python-hexagonal-clean-archi instead.
---

# Python hexagonal, flat

Ports and adapters without the layer ceremony, for **tech products**: a CLI, a Python SDK, an
MCP server, the open-source core of a product whose SaaS comes later. The value kept is the
one that matters for these tools: the same operations behind several entrypoints, adapters you
can swap or add (a SaaS adds its own), tests without the cloud. What goes: one class per use
case, DTOs mirroring entities, four levels of folders.

## Pick the right skill

| The project is… | Use |
|---|---|
| A CLI, SDK, MCP server, library or open-source core; entrypoints call operations in-process; no database of its own | **this skill** |
| An HTTP service with persistence (FastAPI + SQLAlchemy, migrations), a wire format to protect, a team that splits work by layer | `python-hexagonal-clean-archi` |

A tool can outgrow this layout: when it gains an HTTP API backed by its own database, that part
moves to the layered skill. Not before.

## Layout

```
<pkg>/                       single top-level package, no src/ (uv_build: module-root = "")
├── __init__.py
├── core/                    pure rules and models, one module per concept
│   ├── errors.py            <Pkg>Error base + concrete subclasses
│   └── <concept>.py         frozen dataclasses + pure functions
├── ports.py                 every outbound port, as typing.Protocol
├── service.py               the operations: one function each, ports as keyword arguments
├── adapters/                one module per external system, implementing ports
│   └── <system>.py
├── settings.py              env-prefixed settings (<PKG>_*)
├── wiring.py                the only module that builds adapters: lazy, cached
├── cli.py                   entrypoint (Typer): parse → wiring → service → render
└── mcp.py                   entrypoint (later): same operations, other transport
tests/
├── conftest.py              in-memory fakes of the ports
├── test_<concept>.py        core, no fakes needed
├── test_service.py          operations against the fakes
└── test_cli.py              entrypoint with wiring overridden
```

Split a module when it passes ~300 lines or mixes two concepts. When one area grows a set of
its own (ports, rules, operations), give it a sub-package with the same shape
(`<pkg>/iam/{core,ports,service}.py`); keep `wiring.py` and the entrypoints at the top.

## Dependency rule

```
cli.py / mcp.py ──▶ wiring.py ──▶ adapters/ ──▶ ports.py ──▶ core/
        └──────────────▶ service.py ─────────────┘
```

- `core/` imports nothing from the package except `core/`, and no I/O library: no cloud SDK,
  no Typer, no Rich, no Pydantic, no clock, no randomness.
- `ports.py` and `service.py` import `core/` only.
- `adapters/` import `core/` and `ports.py`, plus their SDK.
- Entrypoints import `wiring.py`, `service.py` and `core/`, never an adapter.

Check: deleting `adapters/` and the entrypoints must leave `core/`, `ports.py` and `service.py`
importable and their tests green.

## Ports: Protocols, not ABCs

```python
# ports.py
class QuotaSource(Protocol):
    """Reads quota usage. Read-only."""

    @property
    def description(self) -> str:
        """Where the data comes from, shown with every answer."""
        ...

    def usage(self, project: str) -> list[QuotaUsage]:
        """Raises SourceUnavailableError when the project cannot be read."""
        ...
```

- Structural typing: adapters and fakes match without inheriting; the SaaS can implement a port
  without importing anything but the type.
- Document in the docstring what the port raises: that is part of the contract.
- One port per external capability, not per API call.

## Operations: functions with keyword-only ports

```python
# service.py
def quota_report(
    projects: Iterable[str],
    *,
    source: QuotaSource,
    threshold: float = 0.8,
    clock: Callable[[], datetime],
) -> QuotaReport:
    collected_at = clock()
    findings, unreachable = [], []
    for project in projects:
        try:
            findings += [usage for usage in source.usage(project) if usage.ratio >= threshold]
        except SourceUnavailableError:
            unreachable.append(project)  # unknown, never reported as fine
    return QuotaReport(source=source.description, collected_at=collected_at,
                       findings=tuple(sorted(findings, key=attrgetter("ratio"), reverse=True)),
                       unreachable=tuple(unreachable))
```

- **A function, not a class.** A stateless class with one `execute` method is a function with
  ceremony. The ports are its dependencies, passed explicitly.
- Business inputs positional or keyword, **ports and side-effect providers keyword-only** after `*`.
- `clock`, `nonce`, random generators are injected like ports: tests pin them.
- Rules live in `core/` (`QuotaUsage.ratio`, a `plan_*` function); `service.py` orchestrates
  ports around them. If an operation has an `if` about the business, it probably belongs in `core/`.
- Return **core objects** (frozen dataclasses), not mirrored DTOs. There is no HTTP wire format
  to protect; serialization happens in the entrypoint.

## Wiring: lazy, cached, the only place adapters are built

```python
# wiring.py
@dataclass(frozen=True, slots=True)
class Services:
    quota_report: Callable[[Iterable[str], float], QuotaReport]


def gcp_services(settings: Settings) -> Services:
    @cache
    def quota_source():
        from google.cloud import cloudquotas_v1  # SDK imported on first use only

        from <pkg>.adapters.cloud_quotas import CloudQuotasSource

        return CloudQuotasSource(cloudquotas_v1.CloudQuotasClient(), settings)

    return Services(
        quota_report=lambda projects, threshold: service.quota_report(
            projects, source=quota_source(), threshold=threshold, clock=utc_now
        ),
    )
```

- **Lazy**: `<pkg> --help`, a rejected argument or a failing setting check must not import a
  cloud SDK or look up credentials. Import the SDK inside the factory.
- **Cached**: one client per process.
- `Services` binds the ports once and exposes plain callables to the entrypoints: they never see
  an adapter.
- A different environment (tests, the SaaS, a local emulator) builds a different `Services`:
  no flags inside adapters.

## Entrypoints stay thin

```python
# cli.py
def services() -> Services:  # monkeypatched in tests
    return gcp_services(load_settings())


@app.command()
def quotas(project: list[str], threshold: float = 0.8, output: Output = Output.TABLE) -> None:
    try:
        report = services().quota_report(project, threshold)
    except QuotawatchError as exc:
        err_console.print(f"[red]error:[/] {exc}")
        raise typer.Exit(1) from exc
    render(report, output)
```

- Parse and validate input formats (`24h`, file paths), call one `Services` callable, render.
- Map `<Pkg>Error` to a message and exit code here, once; let unexpected exceptions surface.
- Rendering (Rich table, JSON, Markdown) is entrypoint code, next to the CLI.
- An MCP server or a Python API is one more entrypoint over the same `Services`, never a
  second implementation of an operation.

## Errors

One base class per package in `core/errors.py` (`QuotawatchError`), concrete subclasses for what
a user can act on (`SourceUnavailableError`, `InvalidWindowError`). Adapters translate SDK
exceptions (`NotFound`, `Forbidden`) into them with an actionable message: the missing role,
the setting to fix. Never return an empty result for a source that failed.

## Settings

`pydantic-settings` with an env prefix (`QUOTAWATCH_`), loaded in the entrypoint and passed to
`wiring.py`. A missing setting becomes a `<Pkg>Error` naming the variable. Local values come
from `.envrc` (`direnv-local-env`, `python-uv-direnv`).

## Tests

- **core**: plain objects in, plain objects out; no fakes.
- **service**: in-memory fakes in `conftest.py`, matching the Protocols structurally (no
  inheritance), raising the same errors as the real adapters.
- **adapters**: the SDK client replaced by a small fake, or a pure builder function tested
  directly (`build_query(...)` returning SQL + parameters).
- **entrypoints**: `typer.testing.CliRunner`, with the `Services` factory monkeypatched to one
  built on the fakes.
- Names and bodies follow `unit-test-given-when-then`.

```python
# tests/conftest.py
class FakeQuotaSource:
    description = "fake quotas"

    def __init__(self, usage: dict[str, list[QuotaUsage]], unreachable: set[str] = frozenset()) -> None:
        self._usage, self._unreachable = usage, unreachable

    def usage(self, project: str) -> list[QuotaUsage]:
        if project in self._unreachable:
            raise SourceUnavailableError(project)
        return self._usage.get(project, [])
```

## Building a SaaS on top

The open-source package is the core; the SaaS is another repo that **depends on the published
package** and adds what only it needs:

- its own adapters for the same ports (per-tenant credentials, a cache), and new ports for
  hosted features;
- its own wiring (`tenant_services(tenant)`), and its own entrypoints (HTTP API, chat bot) over
  the same `service.py` operations.

The public surface is therefore `core/`, `ports.py` and `service.py`: keep their names stable and
mark breaking changes in the release notes. Never fork the core to add a SaaS feature; add a
port or a parameter upstream.

## Anti-patterns

| Don't | Why |
|---|---|
| `XxxUseCase` classes with one `execute` method | Ceremony; a function with keyword-only ports is as testable. |
| View DTOs copying core dataclasses field by field | Duplication with nothing to protect; render core objects in the entrypoint. |
| `domain/` + `application/` + `infrastructure/` folders in a CLI | Navigation cost for no boundary the flat layout does not already enforce. |
| Importing an adapter or an SDK from `cli.py` | Breaks the swap point and slows `--help`; go through `wiring.py`. |
| Top-level `from google.cloud import …` in `wiring.py` | Every command pays for the import and the credential lookup. |
| `datetime.now()` inside `core/` or `service.py` | Untestable time; inject `clock`. |
| ABC ports that adapters must inherit | Couples the SaaS and the fakes to the package's class hierarchy; use Protocols. |
| Returning `[]` when a source failed | An unreadable source becomes a false "nothing to report". Raise. |
