"""Captured agy CLI 1.4.7 hook fixtures: sanitization and recorded observations.

Pure file checks over tests/fixtures/agy-1.4.7; no agy, network or LLM calls.
"""
import json
from pathlib import Path
import re
import unittest

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "agy-1.4.7"
ALLOWED_ENV = {"ANTIGRAVITY_CONVERSATION_ID", "ANTIGRAVITY_TRAJECTORY_ID", "ANTIGRAVITY_PROJECT_ID"}


def load(name):
    with open(FIXTURES / name, encoding="utf-8") as stream:
        return [json.loads(line) for line in stream if line.strip()]


class AgyFixtureSanitizationTests(unittest.TestCase):
    def test_no_host_paths_secrets_or_env_values(self):
        forbidden = re.compile(r"/Users/|/home/[a-z]|/tmp/|ghp_|github_pat_|sk-or-|CSRF|PERSONAL_ACCESS")
        for path in sorted(FIXTURES.rglob("*")):
            if path.is_file():
                text = path.read_text(encoding="utf-8")
                self.assertIsNone(forbidden.search(text), f"{path.name}: unsanitized content")

    def test_events_keep_only_allowlisted_env_names(self):
        for name in ("run1-events.jsonl", "run2-events.jsonl"):
            for event in load(name):
                self.assertNotIn("env", event)
                self.assertLessEqual(set(event["inherited_env_names_allowlisted"]), ALLOWED_ENV)

    def test_transcript_content_is_bounded(self):
        for name in ("run1-transcript.jsonl", "run2-parent-transcript.jsonl", "run2-subagent-transcript.jsonl"):
            for step in load(name):
                self.assertLessEqual(len(step["content"]), 600)


class AgyObservationTests(unittest.TestCase):
    def setUp(self):
        self.events = load("run1-events.jsonl") + load("run2-events.jsonl")
        self.parent = load("run2-parent-transcript.jsonl")

    def of(self, kind):
        return [event for event in self.events if event["event"] == kind]

    def test_hook_cwd_is_hooks_dir_and_workspaces_come_from_payload(self):
        for event in self.events:
            self.assertTrue(event["hook_cwd"].endswith("/app/.agents"), event["hook_cwd"])
            paths = event["payload"]["workspacePaths"]
            self.assertEqual([p.rsplit("/", 1)[-1] for p in paths], ["app", "infra"])

    def test_tool_names_and_failed_tool_errors(self):
        tools = self.of("PostToolUse")
        names = {event["payload"]["toolCall"]["name"] for event in tools}
        self.assertEqual(names, {"read_file", "write_file", "edit_file", "run_command",
                                 "invoke_subagent", "send_message"})
        self.assertTrue(names.isdisjoint({"view_file", "write_to_file", "replace_file_content"}))
        failed = [event for event in tools if event["payload"]["error"]]
        self.assertEqual({event["payload"]["toolCall"]["name"] for event in failed}, {"write_file", "edit_file"})
        appended = [event for event in tools if event["payload"]["toolCall"]["args"].get("Append") is True
                    and not event["payload"]["error"]]
        self.assertEqual(len(appended), 1)

    def test_stop_reasons_continuation_and_final_text(self):
        stops = self.of("Stop")
        self.assertEqual({event["payload"]["terminationReason"] for event in stops},
                         {"NO_TOOL_CALL", "TERMINAL_CUSTOM_HOOK"})
        self.assertIn(1, {event["payload"]["executionNum"] for event in stops})
        self.assertIn(False, {event["payload"]["fullyIdle"] for event in stops})
        normal_tails = [event["transcript_tail_at_stop"] for event in stops
                        if "transcript_tail_at_stop" in event
                        and event["payload"]["terminationReason"] == "NO_TOOL_CALL"
                        and event["payload"]["fullyIdle"]]
        self.assertGreaterEqual(len(normal_tails), 4)
        for tail in normal_tails:
            self.assertEqual(tail["type"], "PLANNER_RESPONSE")
        feedback = [s for s in self.parent if s["type"] == "SYSTEM_MESSAGE"
                    and "Stop hook blocked termination: PROBE-STOP-CONTINUE" in s["content"]]
        self.assertEqual(len(feedback), 1)

    def test_session_start_has_no_source_and_skips_resume_and_compact(self):
        starts = self.of("SessionStart")
        for event in starts:
            self.assertNotIn("source", event["payload"])
        run2 = load("run2-events.jsonl")
        parent_id = run2[0]["payload"]["conversationId"]
        self.assertEqual(sum(1 for e in run2 if e["event"] == "SessionStart"
                             and e["payload"]["conversationId"] == parent_id), 1)

    def test_manual_compact_is_a_checkpoint_step_without_step_reset(self):
        checkpoints = [s for s in self.parent if s["source"] == "SYSTEM" and s["type"] == "CHECKPOINT"]
        self.assertEqual(len(checkpoints), 1)
        self.assertTrue(checkpoints[0]["content"].startswith("# Resuming from a compaction"))
        run2 = load("run2-events.jsonl")
        parent_id = run2[0]["payload"]["conversationId"]
        steps = [e["payload"]["initialNumSteps"] for e in run2
                 if e["event"] == "PreInvocation" and e["payload"]["conversationId"] == parent_id]
        self.assertEqual(steps, sorted(steps))

    def test_ephemeral_messages_persist_as_sdk_steps(self):
        ephemeral = [s for s in self.parent if s["type"] == "EPHEMERAL_MESSAGE"]
        self.assertTrue(ephemeral)
        self.assertTrue(all(s["source"] == "SYSTEM_SDK" for s in ephemeral))

    def test_invocation_identity(self):
        keys = [(e["payload"]["conversationId"], e["payload"]["initialNumSteps"]) for e in self.of("PreInvocation")]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertGreater(len([e for e in self.of("PreInvocation") if e["payload"]["invocationNum"] == 0]), 1)

    def test_subagent_parentage_is_in_parent_transcript_before_child_start(self):
        created = [s for s in self.parent if "Created the following subagent:" in s["content"]]
        self.assertEqual(len(created), 1)
        child = re.search(r'"conversationId":\s*"([0-9a-f-]+)"', created[0]["content"]).group(1)
        run2 = load("run2-events.jsonl")
        invoke = next(e for e in run2 if e["event"] == "PostToolUse"
                      and e["payload"]["toolCall"]["name"] == "invoke_subagent")
        self.assertEqual(set(invoke["payload"]) & {"result", "output"}, set())
        child_start = next(e for e in run2 if e["event"] == "SessionStart"
                           and e["payload"]["conversationId"] == child)
        self.assertEqual(child_start["payload"]["lastUserInput"], "")
        self.assertLess(invoke["ms"], child_start["ms"])


if __name__ == "__main__":
    unittest.main()
