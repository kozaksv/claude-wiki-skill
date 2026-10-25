# Wiki Watchdog — W1: спільні контракти v1

**Специфікація r1 для рев’ю · 25.10.2026 · W1 / [#24](https://github.com/kozaksv/claude-wiki-skill/issues/24).**

Основа: [RFC v5 / #21](https://github.com/kozaksv/claude-wiki-skill/issues/21), [погоджена декомпозиція r1 / #23](https://github.com/kozaksv/claude-wiki-skill/issues/23) та [GO-рев’ю з трьома уточненнями W1](https://github.com/kozaksv/claude-wiki-skill/issues/23#issuecomment-6393600114). RFC визначає продуктові вимоги; цей документ визначає межі даних і відповідальність компонентів. Числа й scope RFC не змінюються.

**Статус поставки:** проєкт контрактів і синтетичні приклади. Rust runtime, адаптери, build/CI scaffold та production installation тут не реалізовано. W1 і M0 залишаються відкритими до перевірки їхніх критеріїв. Схеми нижче — семантичні pseudotypes, не готовий SDK або фізичний SQLite DDL.

## Межі та додатки

Watchdog працює лише з ініціалізованими вікі. Markdown/Git зберігають знання; одна локальна SQLite користувача — оперативний стан. Основний агент змінює знання через skill у межах наявного дозволу. Inbox, чернетки знань, автономний commit/push або розширення delegated scope не додаються.

Classic 4.x не потребує Rust. Watchdog 5.x і Jev/OpenRouter активуються явно; локальні правила/capture/облік/health не залежать від Jev. Qwen runtime поза scope; remote GitHub skill окремий.

Додатки: [edition/build profiles](watchdog/v1/edition-profiles.md), [pre-change Git anchor](watchdog/v1/pre-change-git-anchor.md), [bounded fragment](watchdog/v1/bounded-checkpoint-fragment.md). [Contract cases](../../tests/fixtures/watchdog-contracts/v1/contract-cases.json) і [README](../../tests/fixtures/watchdog-contracts/v1/README.md) — синтетичні приклади, не докази runtime.

## Власники й споживачі

W1 володіє спільними контрактами та узгодженням їхніх змін. Runtime-власник реалізує контракт; споживач не створює його паралельну несумісну версію.

| ID | Контракт | Runtime-власник / producer | Споживачі |
|---|---|---|---|
| C01 | Edition/schema/profile layout | W1 — build foundation; W6 — release/activation | W2–W11 |
| C02 | Evidence, source, cursor | W2; W7–W9 надають native evidence | W3–W11 |
| C03 | Scope, discovery, protection | W2 | W3–W10 |
| C04 | NormalizedEvent | W7–W9 → W2 ingestion | W3–W6, W10 |
| C05 | ReminderBoundary | W7–W9 — native mapping; W3 — policy eligibility | W2 reservations, W10 orchestration |
| C06 | Material, checkpoint, need, outcome | W3 через W2 storage | W4, W7–W10 |
| C07 | Jobs, leases, generation, reservations | W2 — механіка; W3/W10 — політика | Усі runtime-компоненти |
| C08 | Pre-change Git anchor | W2 capture/storage; W5 baseline resolution | W5 |
| C09 | Bounded fragment | W2; W7–W9 — дозволені source views | W3, W10; W4 coverage |
| C10 | EvaluatorJob/Result | W3 замовляє; W10 оцінює через W2 jobs | W3, W4 |
| C11 | Usage/export та log receipts | W4 — usage/export; W5 — log | W2 storage, W6 transitions, W11 |
| C12 | Activation, ownership, health, errors | W6 через W2; adapters — manifests | W3–W5, W7–W11 |

W11 перевіряє інтеграцію готових компонентів. Власні інструкції, тести й потрібна регенерація bundle входять у PR відповідного компонента. Runtime-власність не означає окрему БД: усі ledgers, jobs і receipts використовують W2.

## C01. Версії, файлові профілі та compatibility

Program/skill release, wiki schema та SQLite schema незалежні. Classic 4.x і Watchdog 5.x мають `SUPPORTED_WIKI_SCHEMA_MAJORS=[4]`; init schema — 4.0. Program 5.x не запускає міграцію здорової wiki 4.x. SQLite version визначає W2; несумісний writer не допускається.

```text
ResolvedSkillProfile {
  profile_format, edition: classic | watchdog, skill_version,
  supported_wiki_schema_majors, init_schema_version,
  files: destination -> explicit_source, capabilities, development_or_release
}
```

Pseudotype описує resolved profile. Persisted manifest має `compatibility_source` з додатка; support set не дублюється незалежною конфігурацією.

Root `SKILL.md`/`references/*` лишаються Classic sources. `profiles/watchdog/` містить Watchdog-specific sources; `profiles/classic.json` і `profiles/watchdog.json` — explicit mappings. Shared neutral files підключаються явно. Missing required override — build error, не fallback на Classic reflection/telemetry/writer.

W1 ставить мінімальний build/CI scaffold **до merge компонентних instruction PR**, без очікування W6. W6 надалі пакує binary/hooks/resources і реалізує production routing/activation. Development instruction profile не є користувацьким релізом.

No-args `build_skill.py` зберігає shared/remote генерацію; майбутнє `--edition classic|watchdog|all --out build/skill-profiles` збирає відокремлені профілі. Цей spec PR команду не реалізує. Remote GitHub bundle не отримує локальний Watchdog writer/binary requirement. Новий manager не створює Qwen entries; legacy `QWEN.md` у discovery не є runtime support. Деталі та критерії — [додаток](watchdog/v1/edition-profiles.md), **ED**.

## C02. Evidence, source references та typed cursors

```text
Evidence<T> =
  Known { value: T, provenance: observed | declared | derived,
          sources: SourceRef[], derivation_version? }
  | Unknown { reason, sources: SourceRef[] }
SourceRef {
  source_id, kind, harness_profile, scope_ref,
  version_or_watermark: Evidence<SourceVersion>,
  locator: Evidence<TypedCursor>, capture_coverage, availability
}
TypedCursor =
  PayloadField { event_key, field_path }
  | TranscriptRecord { transcript_id, record_key, field_path }
  | FileBytes { file_identity, start, end, verified_record_key? }
  | ProfileCursor { profile_version, cursor_type, value }
```

SQLite record ID ідентифікує запис, але не доводить native event identity/parentage/new turn. `Known(false)` — доведена відсутність ознаки; `Unknown` — недостатній доказ. Прочитаний порожній файл, відсутній файл, unavailable і read error — різні стани.

Byte offset, transcript step, invocation counter і sanitized Unicode scalar offset мають різні типи; mapping потребує доказу. Timestamp не замінює порядок transcript або dedup key. `declared` не маркується observed; `derived` зберігає входи/версію правила. Агрегація зберігає coverage і unknown.

Приклад: `role=Unknown(parent_result_not_visible)` не стає root через порожній prompt. Нерозпізнаний shell дає unknown read coverage; відомий `git status` може дати `Known(false)` для wiki-read. Приклади: **EV**.

## C03. Scope, identity, discovery та protection

```text
Scope {
  user_id, harness_profile,
  worktree_id: Evidence<CanonicalWorktreeId>, wiki_id: Evidence<WikiId>,
  session_id: Evidence<SessionId>, agent_id: Evidence<AgentId>,
  epoch_id: Evidence<EpochId>, role: Evidence<root | child>,
  parent_link: Evidence<ParentLink>
}
resolve_scope(AllowedAnchors, ExplicitTarget?) -> DiscoveryResult
resolve_protection(WikiId, ExactRelativePaths) -> ProtectionResult[]
bind_parent(VerifiedParentLink, expected_version) -> Bound | Existing | Conflict
```

Різні clones/worktrees не об’єднуються за remote URL. Canonicalization не виходить за дозволені boundaries через symlinks/pointers. Unknown scope не підміняється найближчим зручним workspace.

Discovery повторює чинний parser/fixtures: nearest scope, valid pointers, same-level conflict, explicit target, Git boundary. Відсутність sidecar не означає no wiki. `no_wiki` → тиша без init; зареєстрована доступна wiki без index → unhealthy; unavailable диск не є stale_worktree. Failed stat сам не доводить видалення.

AGY anchors — payload workspace paths і доведені tool paths/Cwd, не process cwd чи перший workspace масиву. Ambiguous paths лишаються unattributed. Child read не задовольняє parent consult; early consult дитини потребує підтвердженої wiki-релевантності делегування/paths. SessionStart/code path недостатні. Late binding об’єднує accounting family, не consulted/handled.

Ephemeral вимагає доказу тимчасовості конкретної копії та parent/child: active health зберігається, незалежний timer її не обходить; лише підтверджене штатне видалення завершує реєстрацію. Unknown lifecycle лишається звичайним режимом.

Protection: valid `policy.json` record перемагає, включно з false; absent record → legacy protected/pinned. Corrupt/невстановлений protection блокує відповідну destructive дію, не читання. W4/W5/W6 споживають один resolver. Приклади: **EV**, **ACT**.

## C04. NormalizedEvent

```text
NormalizedEvent {
  contract_version, ingest_id, native_event_key: Evidence<EventKey>,
  source: SourceRef, observed_at, origin: agent | watchdog | harness_service,
  scope: Scope, activation_generation,
  kind: session | tool_result | model_boundary | compact_observed
        | stop | source_observed | declared_outcome | health,
  payload: TypedPayload, limitations[]
}
ToolResult {
  tool_identity, operation_key: Evidence<OperationKey>,
  operation: read | write | create | delete | rename | other | unknown,
  exact_paths[], result: succeeded | failed | partial | unknown,
  read_coverage: full | ranges | unknown,
  content_version: Evidence<ContentVersion>, effect_evidence[], error?
}
```

Native mapper належить версійному адаптеру; W3 не розбирає native JSON. Stable event/cursor identity дає replay dedup; unknown не підміняється timestamp/UUID із претензією на replay-safe доказ. Непідтверджені події не створюють точних counters або retry progress.

Success result і observed effect різні: failed read не зараховується, failed shell не доводить відсутності часткового write; окремий content comparison може довести його. PostInvocation не доводить tool execution. Index read одного рядка — partial, не READ FIRST; index read не підміняє topic read. Unknown shell/MCP coverage локальна до операції й не стирає попередні підтверджені читання.

Own watcher/status/report/repair reads не є consultations агента; own feedback не є новим знанням. Replay read повертає Duplicate без counter increment; новий failed edit зберігається без patch increment. Приклади: **EV**, **ST**.

## C05. ReminderBoundary: invocation, доставка й retry — окремі сигнали

```text
ReminderBoundary {
  boundary_key: Evidence<BoundaryKey>, scope, source,
  invocation_observed: Evidence<bool>,
  purpose: new_turn | external_wakeup | tool_loop | compact_execution
           | stop | own_feedback | unknown,
  delivery_capability: Evidence<DeliveryCapability>,
  scheduled_delivery_eligible: Evidence<bool>,
  advances_retry_clock: Evidence<bool>,
  new_wiki_scope: Evidence<WikiId>,
  stop: Evidence<StopFacts>, exclusions[]
}

StopFacts {
  normal_completion: Evidence<bool>, interrupted: Evidence<bool>,
  cancelled: Evidence<bool>, error_or_limit: Evidence<bool>,
  native_stop_hook_active: Evidence<bool>,
  fully_idle: Evidence<bool>, current_final_source: Evidence<SourceRef>
}
```

Відсутній Stop fact є Unknown, не normal completion і не автоматичний false для error/cancellation. Adapter подає докази межі; W3 застосовує relevance, needs, guards і caps. Спочатку визначається eligibility, лише потім створюється delivery/wait reservation. Факт model call сам не є дозволом доставки або новим retry tick. На одній придатній межі — одна коротка підказка.

### AGY CLI 1.4.7: уточнення погоджених контрактів

- Виконання саме compact не отримує delivery reservation і не просуває retry. `/compact` — сигнал наміру у профілі; успішний перехід epoch вимагає нового native `SYSTEM/CHECKPOINT`.
- Suppression прив’язаний до execution. Failed compact або stale `lastUserInput` не створює epoch і не вимикає наступні нормальні межі назавжди. Якщо phase/identity конкретної межі unknown, це не доказ придатності саме цієї межі.
- Scheduled early consult, pending maintenance і retry використовують підтверджені нові turns/wakeups. `invocationNum==0` — лише одна ознака профілю; не унікальний ID, доказ root-role чи нового користувацького ходу.
- `invocationNum>0` у tool-loop не просуває звичайний retry і не доставляє старий pending maintenance. Вузький виняток — доречний consult вперше підтвердженого нового wiki-scope, з child guards і тими самими caps.
- Replay, власний Stop feedback та unknown boundary identity не просувають лічильник трьох нових придатних меж.

`(conversationId, initialNumSteps)` із capture — кандидат mapping для PreInvocation boundary у цьому профілі, не універсальний ID всіх подій. Native versions/trajectory/error/retry перевіряє W9. W7/W8 доводять власні mapping; Codex service prompt після Stop не скидає наш guard.

PreCompact зберігає checkpoint без мережі й без обіцянки tool-enabled turn. Timer/worker stdout не доставляє повідомлення в idle session. AsyncRewake поза scope. Приклади: **CB**, **ST**.

## C06. Material, checkpoint, need та outcome

```text
MaterialRef {
  material_id, scope, source_refs[], source_versions,
  covered_source_ranges, observed_change_refs[], identity_basis
}
RepresentationRef {
  representation_id, material_refs[], sanitizer_version, selector_version,
  retained_ranges, coverage, representation_fingerprint
}
Checkpoint {
  checkpoint_id, scope, material_refs[], source_watermarks,
  cause_evidence, stop_wait_used, continuation_used
}
Need {
  need_id, kind: consult | consider_update | health,
  scope, checkpoint_ref?, material_refs[], required_evidence[],
  state: pending | emitted | handled | deferred | expired,
  delivery_receipts[], retry_progress, defer_reason?, resume_condition?
}
Outcome {
  outcome_id, need_ref, material_refs[], covered_items[],
  kind: saved | already_covered | no_new_durable_knowledge | deferred,
  evidence: Evidence<OutcomeDetails>, reason_code?, resume_condition?
}
```

Material records незмінні; підтверджено інший зміст/source version → новий record. Інша квота/head+tail/redaction/rendering не поновлює material/checkpoint/Stop credit. Snippet fingerprint не доводить незмінність невидимого залишку.

Checkpoint групує конкретний новий матеріал. Bookkeeping/`готово`/own feedback/service turn не поновлюють continuation. Prefilter враховує змістовну user instruction і final-only висновок; довжина або кількість файлів самі не визначають цінність.

`emitted` означає сформований output, не прочитання чи виконання. `handled` вимагає outcome щодо конкретного матеріалу; одна observed wiki-write не закриває всі висновки. Частковий outcome закриває лише перелічені items. Читання може закрити consult, але не автоматично consider_update. Declared outcome зберігає provenance; додатковий LLM-review для його перевірки не запускається.

Ephemeral emission без outcome допускає один retry C07, далі — deferred з умовою поновлення. Retention/TTL → expired, не handled. Reminder/evaluator result не розширює дозволів.

Startup/clear відкриває контекст без inherited consulted. Підтверджений compact атомарно відкриває epoch тієї самої сесії: consultation скидається, pending та emitted-unhandled незмінного матеріалу переносяться, handled не відновлюється, deferred зберігає умову. Ledger і Stop guards не скидаються. Підтверджений resume відновлює стан; unconfirmed resume та fork не успадковують consultation/handled за схожим шляхом.

Late result перевіряє material refs/generation/outcome: незалежні нові події його не анулюють, змінений матеріал — анулює. Старий epoch ID сам не відкидає result після confirmed compact.

**Приклад:** checkpoint M1 містить рішення A і workaround B. Агент записав A та declared outcome для A; B лишається pending. Новий уривок A з іншою шириною не повертає A в pending. Нове незалежне C створює власний матеріал і не закривається outcome для A. Приклади: **ST**, **CF**.

## C07. Спільні storage/job/reservation primitives

W2 реалізує transactions/locks/dedup/leases/recovery; W3 визначає delivery/wait policy, W10 — API attempts/cost. Одна SQLite, без adapter-local budgets/guards.

```text
ingest(event) -> Inserted | Duplicate | Limited(reason)
read_state(scope, version?) -> StateView | Limited
transact(expected_versions, generation, changes) -> Committed | Conflict | Error
claim_job(job_key, generation, worker_id) -> Lease | Busy | Ineligible
complete_job(lease, result, material_validation) -> Applied | Stale | Deferred
reserve_action(scope, policy_ref, action, guard_key, generation) -> Reservation | Denied
begin_wait(reservation) -> Started | Denied
record_emission(reservation, output_receipt) -> Committed | Conflict
record_no_emission(reservation, proof) -> ReleasedDelivery | Unknown
reserve_api_attempt(job, bounded_cost, policy_ref, generation) -> ApiReservation | Denied
settle_api_attempt(reservation, usage_evidence) -> Settled | CostUnknown
invalidate_generation(expected_generation, transition_ref) -> NewGeneration | Conflict
```

Операції можна об’єднувати транзакційно без зміни інваріантів. `policy_ref` — валідовані W3/W10 rules, не довільні adapter caps. Accounting time runtime, clock/restart behavior зберігають rolling limits; timestamp payload не перезапускає вікно.

Reservation містить scope/family/user, generation, action, budget window, guard key, state та accounting timestamps. Lease містить job ID, generation, власника, expiry, attempt count і fencing/version token. Expired lease не дає нового безкоштовного attempt; crash не стирає витрат/резервів.

Перед wait резервуються wait і delivery. Wait зараховується при початку очікування незалежно від результату, delivery — при emission. Доведена відсутність emission звільняє його резерв; невідомий crash outcome не видає нову безкоштовну спробу. Wait, який уже почався, не повертається через відсутність delivery. Одне Stop message коштує одну delivery unit.

Late binding об’єднує витрачені/зарезервовані slots без поновлення. Unknown parentage не вгадується; user cap діє завжди, protected quota — лише confirmed root Stop. Wiki/task/epoch/restart/disable-enable не скидають ledger.

Generation перевіряється до API start, застосування result і emission. Disable/Classic інвалідує pending jobs/retries; уже відправлений request може завершитися й коштувати грошей. Cost фіксується навіть коли результат не дозволено застосувати. DB corruption зберігається як degraded evidence, а не замінюється порожнім станом.

### Зафіксовані початкові межі RFC v5

| Правило | Значення / область |
|---|---|
| Automatic delivery | Family ≤4; user ≤12 за рухомі 60 хв |
| Stop bypass/wait attempts | Family ≤3; user ≤6 за рухомі 60 хв |
| Family shared / protected | Shared 3 delivery +2 waits; protected 1 delivery +1 wait лише root Stop |
| Root Stop порядок | Спершу shared, потім protected; user/API/guards обов’язкові |
| Ephemeral retry | Максимум один після 3 підтверджених нових придатних меж, без Jev |
| Stop checkpoint | Максимум один bypass/wait і одне continuation |
| Stop wait | До 2 с, раніше native timeout із запасом для запису/output |
| Freshness | ≤1 підказка на family за рухомі 4 год, усередині delivery cap |
| Aging fallback | Початково 50% effective context window у сумісних token units |
| Remote evaluation interval | 60 с від попередньої спроби сесії; події не відсувають eligibility |
| Remote concurrency | 1 на сесію, ≤2 на користувача |
| API attempts | ≤100 на користувача за рухомі 24 год, включно з retries/connection checks |
| API cost | Початково ≤0.10 USD на користувача за рухомі 24 год |
| New material / context pack | ≤4096 Unicode scalars сумарно; W10 pack ≤16 KiB UTF-8 |

Числа — погоджені налаштовувані defaults. Protected quota всередині family cap. Early consult/retry/freshness/health/Stop ділять delivery budget; accounting, repair і explicit commands незалежні від нього.

Aging W3 вимірює новий контекст основної моделі, не ціни Jev. Не підсумовуються повторно передані full input tokens, replay або own feedback. Unknown effective window/tokenizer дає limited; немає fallback на фіксовані chars/token, лічильник invocations або час. Bounded fragment C09 не є виміром повного context volume. Freshness cap не означає обов’язкового очікування чотирьох годин після першого read. Приклади: **ST**, **API**.

## C08. Pre-change Git anchor: межа W2 ↔ W5

W2 захоплює anchor на доведеній межі **до** мутацій. W5 його споживає; поточний чистий HEAD після commit не створює ретроспективної бази.

```text
PreChangeGitAnchor {
  anchor_id, scope, interval_id, capture_epoch, capture_generation,
  source_event, typed_cursor, boundary_evidence,
  git_object_format, head_oid, tree_oid,
  coverage: paths + clean_index + clean_worktree + untracked_state,
  captured_order, provenance
}
capture_pre_change(scope, boundary_evidence) -> Captured | Existing | NotCaptured
get_log_baseline(scope, explicit_paths) -> VersionedPerPathBaseline
```

Capture потребує initialized scope, читаємі coherent Git objects/state, clean covered wiki-state і підтверджений pre-change timing. Dirty/unknown/race/late discovery дають NotCaptured; пізній worker цього не виправляє. Unrelated dirty paths поза coverage не заважають.

Anchor незмінний через replay/discovery/compact/new HEAD. Успішні per-path receipts пріоритетні; receipt P не пересуває базу незалогованого Q. W2 дає versioned read/CAS; W5 серіалізує writers і перевіряє використану версію. Pending pins свою базу.

Anchor, створений на новому SessionStart, не є базою для операції до `captured_order` цього інтервалу. Якщо належність операції до охопленого інтервалу не підтверджена, потрібні receipt або explicit base/commit/range; інакше результат — `needs_baseline`, а не `unchanged`.

Без бази → `pending: needs_baseline` з продовженням `--base/--commit/--range` під тим самим operation ID, без manual op begin/ID/history backfill. Shallow missing parent не є root commit. Валідна база доступна offline helper після disable без monitoring/API. Повні правила — [додаток](watchdog/v1/pre-change-git-anchor.md), **ANCHOR**.

## C09. Спільний bounded checkpoint fragment

W2 реалізує primitive без Jev; W7–W9 доводять allowed source/freshness; W3 використовує локально, W10 додає wiki search/context pack.

```text
capture_fragment(VerifiedSourceViews[], SelectionPolicy, LowerQuotas?)
  -> BoundedCheckpointFragment | Limited | Unavailable
BoundedCheckpointFragment {
  checkpoint_id, material_refs[], representation_ref,
  segments: {source_ref, whole|head|tail, sanitized_scalar_position, text}[],
  retained_scalar_count, retained_utf8_bytes, truncated,
  gaps[], omitted_sources[], final_text_status, limitations[]
}
```

4096 Unicode scalars — сумарна квота нового матеріалу, не per source/head/tail. Source exclusions/redaction передують відбору. Long final початково ділить свою квоту порівну між head/tail; reader отримує справжній хвіст current completion, з валідними scalar boundaries та explicit gap.

Native cursor і sanitized offset окремі: redaction змінює довжину. Verified end допускає end-relative scalar offset; unknown total не вигадується. Null/stale/unavailable final не замінюється попереднім. Prefix-only/invalid/torn-record capture не видається за повний head+tail. Own feedback/service sources виключаються за provenance, не substring-фільтром користувацького тексту.

W10 pack ≤16,384 UTF-8 bytes включає metadata/wiki excerpts; byte cap може зменшити scalar quota. Static API criteria/protocol overhead окремо bounded і повністю chargeable. Missing match у вибірці не доводить відсутності знання в wiki. Retained fragment не є total context volume для aging.

W2 визначає bounded I/O/record/lifetime limits; SQLite не копіює повний transcript. Деталі/invalid cases — [додаток](watchdog/v1/bounded-checkpoint-fragment.md), **CF**.

## C10. EvaluatorJob/Result і bounded Stop orchestration

```text
EvaluatorJob {
  job_id, checkpoint_ref, need_refs[], scope, activation_generation,
  material_refs[], representation_refs[], context_pack_fingerprint,
  wiki_evidence_fingerprint, rules_version, requested_model,
  lease_ref, attempt_state, created_at, eligibility
}
EvaluatorResult {
  job_id, decision: no_action | consult_wiki | consider_update | insufficient_evidence,
  evaluated_material_refs[], evidence_limits[], rules_version,
  requested_model, actual_model: Evidence<ModelId>,
  usage: Evidence<Usage>, response_provenance
}
```

W3 prefilter передує job/wait: service/replay/відомий diff не кандидати; read-only final чи коротке правило можуть бути. Incomplete evidence не дозволяє глобальне «нічого нового/ніде не покрито». W10 оцінює дані без tools/прав запису; валідовані рішення/атомарні відповіді перетворюються на Rust templates. Invalid result не застосовується. Compatible model налаштована явно за RFC §8, без hidden latest/chat fallback.

SessionStart/tool/PreInvocation/PreCompact не чекають мережі. Stop одноразово очікує той самий leased job у deadline C07: новий candidate, normal completion, невикористаний continuation, відкриті native/own guards, generation/API/wait/delivery reservations; AGY також fullyIdle. `stop_hook_active=true` → лише облік.

Retries поза Stop wait. Timeout сам не створює continuation; local fallback потребує конкретного приводу й бюджету. Unresolved need лишається pending/deferred; late result не будить idle та повторно перевіряється за C06/C07.

До кожної спроби API резервується обґрунтований upper bound усього input. Unknown usage/timeout не є нулем чи автоматичним refund; retry отримує новий reservation. Немає обґрунтованої ціни → remote paused, local mode працює. Cache враховує material/wiki/representation/rules/requested+actual model provenance.

Remote дозволяє лише ключ, явно налаштований для сторожа, не випадковий env key. Auth failure не дає нескінченні retries; повний env не знімається, AGY attribution має explicit ID allowlist. Ключ не зберігається у SQLite/logs/context. Приклади: **API**, **ST**, **CF**.

## C11. Usage/export та log receipts — різні операції

### W4: механічний облік і sidecar export

```text
UsageContribution {
  contribution_id, event_or_diff_refs, scope, page, metric,
  amount, provenance, source_watermarks, owner_interval_ref, completeness
}
OwnerInterval {
  interval_id, scope, owner: classic | watchdog | dual_owner | unknown,
  start_snapshot, start_boundary, end_boundary?, generation, evidence
}
ExportReceipt {
  export_id, scope, generation, source_watermarks,
  included_contributions[], expected_before_state,
  full_after_totals, sidecar_receipt, phase, limitations[]
}
prepare_export(scope, baseline_version) -> Prepared | Pending | Unavailable
recover_or_commit_export(export_id, observed_sidecar) -> Committed | Pending
```

Observed reads/patches і derived link additions зберігаються окремо. `use_count` означає додані wikilinks, не поточний indegree чи доказ використання знання. Replay не збільшує counters; невідомі дії не компенсуються ручними bumps. SQL reports позначають coverage, provenance, unknown cost і лише кореляцію reminder→action. W4 готує агрегати перед retention W2; SQL-cleanup не видаляє Markdown історію.

Початковий sidecar baseline фіксується один раз до Watchdog accounting. Corrupt/unavailable не є порожнім. Classic delta приймається лише за доведений exclusive owner interval: поточні повні totals мінус повні totals на його початку. Overlap/negative/reset/невизначений rename не домислюються. При 100→Watchdog+10→export110→Classic+5→115 Classic delta дорівнює 5.

Export: SQLite prepare → directory lock і atomic sidecar write з `_watchdog` receipt → SQLite commit. Один незавершений export на wiki. Receipt після crash завершує DB phase без другого додавання; без нього потрібний підтверджений before-state. Невідомий overlap contribution не додається повторно. Зберігаються чужі поля, protection і справжні timestamps; heartbeat не підробляється. Failure не блокує disable/Classic. Приклади: **EX**.

### W5: явний log helper

```text
LogReceipt {
  operation_id, scope, explicit_paths[], baseline_ref_vector,
  before_path_states, after_path_states, change_set_fingerprint,
  summary, entry_marker, prepared_entry_hash, touched_log_paths[],
  rotation_plan?, recovery_attempt?, phase, result, limitations[]
}
append_log(scope, operation, explicit_paths, summary, explicit_git_basis?)
  -> written | already_written | unchanged | failed_before_write | pending
```

Агент один раз явно викликає helper для дозволеної зміни; hooks не пишуть `log.md`. ID автоматичний, helper не виконує commit/push. Content/existence comparison обов’язковий для переданих paths незалежно від hooks. Delete — доведена відсутність, rename включає обидва paths; unrelated paths не додаються.

Operation ID/receipt прив’язані до baseline version і конкретного change set. Однакові summary/final hash не зливають окремі A→B→A→B операції. Replay незмінного change set повертає той самий receipt. Підготовлений marker зберігається в live log та shards; сам marker без повного entry/after-state не є success.

Кожний append серіалізований і atomic. Rotation plan до файлових змін фіксує exact before/after, peel boundaries/hash, shard path/hash, retained tail і власний entry. Shard публікується durable з no-replace до trim live log. Один pending план на wiki; recovery не обчислює новий peel.

За matching shard чисті suffix additions допускають B+S→A+S або вже A+S→commit. Durable recovery-attempt фіксує input/suffix/target hash; S не стає власним внеском. Зміна середини/Archived, partial entry, missing shard після trim або неочікуваний marker дають pending. Перед replacement перевіряється observed state; зовнішній writer, що ігнорує lock, не оголошується повністю виключеним.

`failed_before_write` вимагає доказу відсутності запису і дозволяє manual fallback. Timeout/crash спершу перевіряє receipt/marker у live log **і shards**; pending не дозволяє сліпий append. `unchanged` не запускає fallback. Offline helper працює при disabled monitoring без hooks/API. Log failure не блокує дозволені wiki edits і не видається за успішний запис. Приклади: **LOG**, **ANCHOR**.

## C12. Activation, ownership, health та результат операції

```text
ActivationProfile {
  user_scope, edition, pinned_bundle_id, pinned_bundle_path,
  selected_harnesses, generation, monitoring_enabled,
  explicit_disabled_scopes[], scheduler_state, compatibility
}
OwnershipRecord {
  manifest_version, component, config_location, entry_key,
  expected_signature, ownership: owned | foreign | ambiguous,
  intended_enabled, generation
}
HealthFinding {
  finding_id, scope, component, kind, evidence,
  ownership, repair_eligibility, repeated_failure_key, status
}
Result<T> =
  Ok(T) | Limited(T?, reasons[]) | Deferred(reason, resume_condition)
  | Error { code, phase, scope, side_effect: none | committed | unknown,
            retryability, bounded_details }
```

Default installer зберігає поточну edition, новому користувачу — Classic. W6 journal: prepare → jobs/DB compatibility → owned registrations/exports → ready. Symlink не робить весь transition атомарним; mixed state потребує recovery/rollback.

Процес використовує pinned compatible bundle. System installation не активує user profile: root не обходить homes; DB/config/key/runtime особисті. Disable інвалідує jobs без export-обходу; switch Classic викликає best-effort W4 export, failure не блокує перехід. Видалення даних — окрема явна дія.

Один ownership classifier для install/audit/repair. Foreign/ambiguous entries не переписуються; intentional disable не ремонтується. Owned legacy Qwen entries від’єднуються до ready Watchdog; failure зупиняє activation. Новий manager не створює Qwen entries також при switch Classic.

Health охоплює відомі installs/registered projects на подіях і рідкому user timer, без global scan. Missing scheduler явний. Stale heartbeat — unconfirmed; потрібна registration/executable/write failure або missed known eligible event. Rust робить вузький owned config repair; змістові wiki fixes — основний агент із чинним дозволом/protection.

Результат самої repair операції записується без post-repair LLM review, synthetic probe або повного rescan. Repeated failure має backoff/один сигнал. Corrupt state не замінюється порожнім; unknown side effect не є failed_before_write. Помилка не блокує головну задачу. Adapter формує власний native output, без перенесення Claude JSON; diagnostics не містять secrets/raw env/transcripts. Приклади: **ACT**, **EV**.

## Поточна доказовість адаптерів і відкриті gaps

Джерела матриці — [RFC v5 §6.1](https://github.com/kozaksv/claude-wiki-skill/issues/21), [GO-уточнення AGY](https://github.com/kozaksv/claude-wiki-skill/issues/21#issuecomment-6387609750) і [pinned PR #22](https://github.com/kozaksv/claude-wiki-skill/tree/53dbd68cf67108bf4546e45f972f310b75bf66c7/tests/fixtures/agy-1.4.7). Документація, capture, normalized synthetic case та робота власного адаптера — різні рівні доказів.

| Профіль | Наявний доказ | Що не оголошено готовим / власник |
|---|---|---|
| Claude Code | У RFC зафіксовано documented hooks/final field/compact contract | W7 перевіряє конкретні версії, actual payload/output, Stop guards, long-final та pre-change timing |
| Codex CLI | У RFC зафіксовано documented lifecycle/Stop/compact contract | W8 перевіряє nullable final, service prompt/retry boundaries, native versions та actual reader |
| AGY CLI 1.4.7 | Sanitized capture PR22: successful read, Append write, failed edit, manual compact, child correlation, ephemeral behavior | Це не реалізація Watchdog. W9 доводить mapping, recovery і delivery повним adapter run |
| AGY final text | Capture містить початок final; Stop logger обмежений 200 символами, transcript steps — 600 | W9 має отримати й перевірити справжній tail довгого current final |
| AGY parentage | Parent transcript result може довести child ID | Видимість result до першого child hook не доведена; до неї unknown, потім late binding |
| AGY інші capabilities | Відсутні докази у цих captures | W9: auto-compact, successful edit, PreToolUse, branch/share, IDE/2.0, failed-compact/stale-input сценарії |

SessionStart/source, tool names і поля не узагальнюються між профілями. Непідтверджена capability лишається unknown/unsupported із конкретним reason; вона не блокує нормалізовані W2/W3 contract tests і не маскується stub success. Main-model context estimator/ефективне window доводяться W3 разом із відповідним адаптером; W10 evaluator pricing цього доказу не надає.

## Мінімальні contract cases і exit W1 / M0

Companion JSON має stable IDs, synthetic provenance, normalized given/steps/input та expected outcomes. Він визначає контракт; виконання самих прикладів чи перевірка JSON не доводить Rust implementation/native protocol. Raw captures PR22 залишаються окремим джерелом.

| Група | Контракти / перевірка |
|---|---|
| ED | C01: два профілі, schema compatibility, source isolation |
| EV | C02–C04/C12: evidence, scope, tool success/partial/unknown, errors |
| CB | C05: AGY compact/tool-loop/verified retry/new-scope exception |
| ST | C05–C07/C10: outcome, caps, Stop, compact race, aging, generation |
| ANCHOR | C08/C11: pre-change timing, commit-before-helper, per-path baselines |
| CF | C09/C10: aggregate scalar/byte quota, head+tail, freshness, representation |
| API | C07/C10: attempts, cost reservation, unknown usage |
| EX | C11: owner intervals і двофазний export/recovery |
| LOG | C11: operation identity, atomic log/rotation/fallback |
| ACT | C03/C12: activation/health та scope lifecycle |

W1 acceptance лишається відкритим:

- [ ] Контракти C01–C12 і три додатки погоджені; кожний producer/consumer прийняв unknown/error та ownership boundaries.
- [ ] Є мінімальні success/unknown/error contract cases; їхні IDs стабільні та mapped на приймання компонентів і AC01–AC32 плану.
- [ ] Мінімальний edition build/CI scaffold реалізовано й перевірено: root Classic, окремий Watchdog, remote GitHub independence, explicit schema support.
- [ ] Shared fixtures/schema validation runnable без Rust runtime та Jev; це окремо від acceptance реалізації.
- [ ] Відсутні native captures мають власників; жодний gap не оголошено supported через synthetic case.
- [ ] W2/W3 можуть реалізовувати нормалізовані контракти; W4 export тестується без W6, W5 — без W4, adapters — без production installer.

M0 не вимагає повного live покриття всіх харнесів. M1 доводить локальний Claude event→state→reminder→outcome; M2 додає user lifecycle/health/statistics/log; M3 — повну поставку. Closure W1 не закриває parent acceptance, а M2 не закриває W6/W11.

Зміна shared contract оформлюється разом із власником і всіма зачепленими споживачами, оновлює версію/fixtures і описує compatibility. Зміна чисел або продуктових інваріантів потребує явної зміни RFC, а не локальної правки adapter.

## Джерела репозиторію

Snapshot: [a8e1faf, skill 4.12.1](https://github.com/kozaksv/claude-wiki-skill/tree/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8). Власного wiki index немає; джерела — RFC/review/code. Детальні pinned code citations для build/schema/reader та capture provenance наведено в додатках.

Спільна чинна семантика: [reader/discovery](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/reader-core.md) і [writer/protection](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/writer-core.md).

