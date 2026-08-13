# Settled-леджер циклу v46-qwen

Закриті вердикти циклу (споживаються движком через parseSettled; кап 12000 симв).
НЕ дублювати цю секцію в інших файлах — джерело рівно одне.

## Settled

- id: s1
  verdict: ⛔
  text: T5 (hooks/lib/settings-lock.sh) — жодного lease-renewer, фонових процесів, нових env-перемикачів чи нових пробників живості. Буквальний перенос наявного mkdir-мутекса, «нуль зміни поведінки». Pre-existing обмеження (kill -0 EPERM cross-UID, hidepid=2/procfs, відсутність lease-продовження, TTL LOCK_MAX_AGE) — follow-up P2/P3 у леджер, НЕ blocking задачі.
  why: Кандидат рану №2 виріс у 528-рядковий lib із renewer-ом, зловив 2 security-P1 у власному новому механізмі (kill_renewer 3s bound; hidepid=2 EPERM) і ескалював NEEDS_HUMAN. Лок-файли живуть у per-user $HOME — cross-UID сценарії поза моделлю загроз скіла. Кандидата відхилено (reject bf63984), скоуп пінований у T5 п.9.
  source: контролер циклу з повною автономією від користувача, 2026-08-13, після рану wf_961d43eb-003; план T5 п.9; refs/fp-failed/2c3a30863dc5d832-v46-qwen-5
