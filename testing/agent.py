#!/usr/bin/env python3
"""
Spoke UI Testing Agent
Uses Claude Computer Use to drive the Spoke app in the Xcode iPhone Simulator.

Setup (one-time):
    brew install cliclick
    pip3 install anthropic
    export ANTHROPIC_API_KEY=sk-...

Usage:
    python3 testing/agent.py "Create a task called Buy milk"
    python3 testing/agent.py "Mark the first task as complete"
    python3 testing/agent.py          # prompts interactively
"""

import anthropic
import base64
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

try:
    from PIL import Image as _PIL_Image
    _PIL_AVAILABLE = True
except ImportError:
    _PIL_AVAILABLE = False

# ── Config ────────────────────────────────────────────────────────────────────
SCREENSHOT_PATH = "/tmp/spoke_agent.png"
MAX_STEPS       = 30
STEP_DELAY      = 1.0   # seconds to wait after each UI action

# Logical (non-retina) screen resolution — screencapture output is scaled to this
# before being sent to the API so coordinates match cursor space.
DISPLAY_WIDTH   = 1512
DISPLAY_HEIGHT  = 982

# Mic button detection region (fraction of display).
# Taps landing here trigger on_mic_tap instead of a plain click.
# Adjust if your Simulator is positioned differently.
# Mic region is computed dynamically from the Simulator window bounds at runtime.
# These are fallback fractions of the full display used only if detection fails.
MIC_X_MIN_FRAC = 0.38
MIC_X_MAX_FRAC = 0.62
MIC_Y_MIN_FRAC = 0.82
# ──────────────────────────────────────────────────────────────────────────────

client = anthropic.Anthropic()


# ── Screenshot ────────────────────────────────────────────────────────────────

def capture() -> str:
    """Take a full-screen screenshot, scale to logical resolution, return base64."""
    subprocess.run(["screencapture", "-x", SCREENSHOT_PATH], check=True)
    # Retina screens capture at 2x; scale down so pixel coords == cursor coords
    subprocess.run(
        ["sips", "--resampleWidth", str(DISPLAY_WIDTH),
         SCREENSHOT_PATH, "--out", SCREENSHOT_PATH],
        capture_output=True, check=True,
    )
    return base64.standard_b64encode(Path(SCREENSHOT_PATH).read_bytes()).decode()


def _find_mic_button_by_color() -> Optional[tuple]:
    """
    Scan the BOTTOM third of the current screenshot for the coral mic button
    and return its (x, y) center in logical screen coordinates.  Requires Pillow.

    Restricting to the bottom third avoids false matches on coral filter pills
    and date badges that appear throughout the task list.
    Coral color: #FF6147 ≈ (255, 97, 71).
    """
    if not _PIL_AVAILABLE:
        return None
    try:
        img = _PIL_Image.open(SCREENSHOT_PATH).convert("RGB")
        w, h = img.size
        # Only look in the bottom third of the screen — the mic button is always there.
        bottom_start = h * 2 // 3
        crop = img.crop((0, bottom_start, w, h))
        # Downsample 3× for speed
        small = crop.resize((w // 3, (h - bottom_start) // 3), _PIL_Image.NEAREST)
        sw, sh = small.size
        data = list(small.getdata())
        xs, ys = [], []
        for i, (r, g, b) in enumerate(data):
            if r > 210 and 40 < g < 160 and 20 < b < 130 and r > g + 60 and r > b + 60:
                xs.append((i % sw) * 3)
                ys.append(bottom_start + (i // sw) * 3)
        if len(xs) < 20:
            print("  ⚠️  Color scan: not enough coral pixels in bottom third — falling back to fractions")
            return None
        cx, cy = sum(xs) // len(xs), sum(ys) // len(ys)
        print(f"  🎯 Color scan found mic button at ({cx}, {cy})  [{len(xs)} coral pixels]")
        return cx, cy
    except Exception as e:
        print(f"  ⚠️  Color scan failed ({e})")
        return None


# ── Input execution ───────────────────────────────────────────────────────────

def _get_simulator_mic_region() -> tuple[int, int, int, int]:
    """
    Return (x_min, x_max, y_min, y_max) for the mic button in screen coordinates,
    derived from the actual Simulator window position.
    Falls back to full-display fractions if the window can't be found.
    """
    script = '''
    tell application "System Events"
        tell process "Simulator"
            set w to first window whose name contains "iPhone"
            set pos to position of w
            set sz to size of w
            return (item 1 of pos) & "," & (item 2 of pos) & "," & (item 1 of sz) & "," & (item 2 of sz)
        end tell
    end tell
    '''
    try:
        result = subprocess.run(["osascript", "-e", script],
                                capture_output=True, text=True, timeout=5)
        parts = [int(v.strip()) for v in result.stdout.strip().split(",")]
        wx, wy, ww, wh = parts
        # Use a wide, permissive region so any tap in the lower portion of the
        # Simulator window triggers the mic handler.
        x_min = wx + int(ww * 0.20)
        x_max = wx + int(ww * 0.80)
        y_min = wy + int(wh * 0.75)
        y_max = wy + wh
        # Estimate mic button center for injecting into the agent's first message.
        # iPhone screen content area: ~10% chrome at top, ~5% at bottom.
        # Mic button sits at ~88% of the screen content height.
        mic_x = wx + ww // 2
        mic_y = wy + int(wh * (0.10 + 0.85 * 0.88))
        print(f"  📍 Simulator window: origin=({wx},{wy}) size=({ww}x{wh})")
        print(f"  📍 Mic detection region: x=[{x_min},{x_max}] y=[{y_min},{y_max}]")
        print(f"  📍 Estimated mic button center: ({mic_x}, {mic_y})")
        return x_min, x_max, y_min, y_max, mic_x, mic_y
    except Exception as e:
        print(f"  ⚠️  Could not detect Simulator window ({e}), using display fractions")
        return (
            int(MIC_X_MIN_FRAC * DISPLAY_WIDTH),
            int(MIC_X_MAX_FRAC * DISPLAY_WIDTH),
            int(MIC_Y_MIN_FRAC * DISPLAY_HEIGHT),
            DISPLAY_HEIGHT,
            DISPLAY_WIDTH // 2,
            int(MIC_Y_MIN_FRAC * DISPLAY_HEIGHT) + 40,
        )


# Cached mic region — populated once per run() call
_mic_region = None  # type: Optional[tuple]


def _is_mic_tap(x: int, y: int) -> bool:
    if _mic_region is None:
        return (
            MIC_X_MIN_FRAC * DISPLAY_WIDTH <= x <= MIC_X_MAX_FRAC * DISPLAY_WIDTH
            and y >= MIC_Y_MIN_FRAC * DISPLAY_HEIGHT
        )
    x_min, x_max, y_min, y_max = _mic_region[0], _mic_region[1], _mic_region[2], _mic_region[3]
    return x_min <= x <= x_max and y_min <= y <= y_max


def execute(action: dict, on_mic_tap=None):
    """
    Execute one computer-use action.

    on_mic_tap: optional callable(x, y) invoked instead of a plain click when
    the agent taps the mic-button region.  Use this to inject voice audio.
    """
    kind = action["action"]

    if kind == "screenshot":
        return  # We always snapshot after every step

    elif kind in ("left_click", "right_click", "double_click"):
        x, y = action["coordinate"]
        if on_mic_tap and kind == "left_click" and _is_mic_tap(x, y):
            # Always click the actual detected mic center, not the agent's estimate.
            if _mic_region and len(_mic_region) >= 6:
                actual_x, actual_y = _mic_region[4], _mic_region[5]
            else:
                actual_x, actual_y = x, y
            on_mic_tap(actual_x, actual_y)
            return
        _click(x, y, kind)

    elif kind == "left_click_drag":
        sx, sy = action["start_coordinate"]
        ex, ey = action["coordinate"]
        _drag(sx, sy, ex, ey)

    elif kind == "mouse_move":
        x, y = action["coordinate"]
        _cliclick(f"m:{x},{y}")

    elif kind == "type":
        _type(action["text"])

    elif kind == "key":
        _key(action["text"])

    elif kind == "scroll":
        x, y   = action["coordinate"]
        dy     = -action.get("amount", 3) if action.get("direction", "down") == "down" else action.get("amount", 3)
        _cliclick(f"m:{x},{y}")
        time.sleep(0.1)
        subprocess.run(["osascript", "-e",
            f'tell application "System Events" to scroll at {{{x}, {y}}} with delta x 0 y {dy}'],
            capture_output=True)


def _click(x: int, y: int, kind: str = "left_click"):
    flag = {"left_click": "c", "right_click": "rc", "double_click": "dc"}[kind]
    r = _cliclick(f"{flag}:{x},{y}")
    if r != 0:
        subprocess.run(["osascript", "-e",
            f'tell application "System Events" to click at {{{x}, {y}}}'],
            capture_output=True)


def _drag(sx: int, sy: int, ex: int, ey: int):
    r = subprocess.run(["cliclick", f"dd:{sx},{sy}", f"du:{ex},{ey}"],
                        capture_output=True)
    if r.returncode != 0:
        subprocess.run(["osascript", "-e", f"""
            tell application "System Events"
                set the mouse position to {{{sx}, {sy}}}
                delay 0.15
                set the mouse position to {{{ex}, {ey}}}
            end tell"""], capture_output=True)


def _type(text: str):
    r = subprocess.run(["cliclick", f"t:{text}"], capture_output=True)
    if r.returncode != 0:
        escaped = text.replace('"', '\\"')
        subprocess.run(["osascript", "-e",
            f'tell application "System Events" to keystroke "{escaped}"'],
            capture_output=True)


def _key(key: str):
    subprocess.run(["osascript", "-e",
        f'tell application "System Events" to keystroke key "{key}"'],
        capture_output=True)


def _cliclick(cmd: str) -> int:
    r = subprocess.run(["cliclick", cmd], capture_output=True)
    return r.returncode


# ── Agent loop ────────────────────────────────────────────────────────────────

SYSTEM = """You are a UI testing agent for an iOS app called Spoke, open in the Xcode iPhone Simulator.

About Spoke:
- Voice-first task manager — the coral mic button at the bottom creates/edits tasks
- Tap mic once to start recording, tap again to stop (or hold and release)
- Tasks appear in a list grouped by date (Today / Yesterday / This Week / Earlier)
- Swipe LEFT on a row → Done; swipe RIGHT → Delete
- Tap a row to open the task detail sheet
- Filter pills appear under the "spoke •" wordmark when tasks have tags

How to interact with the Simulator:
- The iPhone screen is the white/dark panel inside the Simulator window
- Click only within that panel — avoid the Simulator chrome and Xcode
- After every action take a screenshot to verify the result before moving on
- If an action had no effect, try clicking slightly closer to the element center

MICROPHONE BUTTON LOCATION:
The coral (red-orange) circular mic button is fixed at the very bottom-center of the iPhone screen.
It is BELOW the task list — not inside it. Look for it in the bottom 15% of the phone screen.
To find it: take a screenshot, identify the iPhone screen boundaries, then click the horizontal
center of the phone screen at roughly 90% of the way down.
Do NOT tap task rows when trying to activate the mic.

BEFORE TAPPING THE MIC — ALWAYS DO THIS FIRST:
Task rows near the bottom of the list can overlap the mic button tap area. To avoid
accidentally opening a task detail sheet instead of activating the mic:
1. Scroll the task list UP (scroll toward the top) so the last task row moves away from
   the mic button. Scroll by clicking in the middle of the list and dragging upward.
2. Verify in a screenshot that the bottom of the list is well above the mic button.
3. Only then tap the mic button.
If a task detail sheet opens by accident, dismiss it (tap the grey area above the sheet or
drag it down), scroll the list up, and try again.

Be methodical: describe what you see → state what you will do → do it → verify."""


def _prune_screenshots(messages: list, keep_last: int = 4):
    """
    Replace image payloads in older tool-result messages with a short text note,
    keeping only the most recent `keep_last` screenshots.
    This prevents the message history from growing too large for the API.
    """
    # Collect indices of user messages that contain tool_result images
    image_indices = [
        i for i, msg in enumerate(messages)
        if msg["role"] == "user"
        and isinstance(msg.get("content"), list)
        and any(
            isinstance(b, dict) and b.get("type") == "tool_result"
            and any(isinstance(c, dict) and c.get("type") == "image"
                    for c in (b.get("content") or []))
            for b in msg["content"]
        )
    ]
    for i in image_indices[:-keep_last]:
        for block in messages[i]["content"]:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                block["content"] = [{"type": "text", "text": "[screenshot removed]"}]


def run(goal: str, system: str = SYSTEM, max_steps: int = MAX_STEPS,
        on_mic_tap=None) -> list[str]:
    """
    Run the agent loop. Returns a list of all text blocks emitted by the model
    (useful for callers that want to capture the session transcript).
    """
    global _mic_region
    print(f"\n🤖  {goal}\n{'─' * 60}")
    transcript: list[str] = []
    _mic_region = _get_simulator_mic_region()

    # Take the initial screenshot, then try to find the mic button by color.
    # This gives the agent the exact coordinates rather than a guess.
    initial_screenshot = capture()
    mic_coords = _find_mic_button_by_color()
    if mic_coords:
        mic_x, mic_y = mic_coords
        coord_hint = (
            f"\n\nIMPORTANT: The coral mic button center has been detected at EXACTLY "
            f"({mic_x}, {mic_y}) in screen coordinates. You MUST click at ({mic_x}, {mic_y}) "
            f"to activate the mic — do NOT click higher on the task list."
        )
        # Wide detection region around the found button (±200px vertically, ±150px horizontally)
        # so the agent's visual estimate doesn't have to be pixel-perfect.
        _mic_region = (mic_x - 150, mic_x + 150, mic_y - 200, mic_y + 200, mic_x, mic_y)
    elif len(_mic_region) >= 6:
        mic_x, mic_y = _mic_region[4], _mic_region[5]
        coord_hint = (
            f"\n\nIMPORTANT: The mic button center is estimated at ({mic_x}, {mic_y}) "
            f"in screen coordinates. Click there to activate the mic — do NOT click higher "
            f"on the task list."
        )
    else:
        coord_hint = ""

    messages = [{
        "role": "user",
        "content": [
            {"type": "image",
             "source": {"type": "base64", "media_type": "image/png", "data": initial_screenshot}},
            {"type": "text",
             "text": f"Goal: {goal}\n\nThis is the current screen. Please achieve the goal.{coord_hint}"},
        ],
    }]

    tools = [{
        "type": "computer_20250124",
        "name": "computer",
        "display_width_px":  DISPLAY_WIDTH,
        "display_height_px": DISPLAY_HEIGHT,
    }]

    for step in range(1, max_steps + 1):
        print(f"\n── Step {step} {'─' * 50}")

        response = client.beta.messages.create(
            model="claude-opus-4-5-20251101",
            max_tokens=4096,
            system=system,
            tools=tools,
            messages=messages,
            betas=["computer-use-2025-01-24"],
        )

        tool_uses = []
        for block in response.content:
            if hasattr(block, "text") and block.text:
                print(f"\n{block.text}")
                transcript.append(block.text)
            if block.type == "tool_use":
                tool_uses.append(block)
                a = block.input
                detail = a.get("coordinate", a.get("text", ""))
                print(f"  → {a['action']}  {detail}")

        if response.stop_reason == "end_turn" or not tool_uses:
            print("\n✅  Agent finished.")
            break

        messages.append({"role": "assistant", "content": response.content})

        tool_results = []
        for tool_use in tool_uses:
            execute(tool_use.input, on_mic_tap=on_mic_tap)
            time.sleep(STEP_DELAY)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tool_use.id,
                "content": [{
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png",
                               "data": capture()},
                }],
            })

        messages.append({"role": "user", "content": tool_results})

        # Prune old screenshots to stay within context limits.
        # Keep the last KEEP_SCREENSHOTS tool-result images; replace older ones with text.
        _prune_screenshots(messages, keep_last=4)

    else:
        print(f"\n⚠️  Reached {max_steps} steps without completing.")

    return transcript


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    goal = " ".join(sys.argv[1:]).strip()
    if not goal:
        goal = input("What should the agent test? → ").strip()
    if not goal:
        goal = "Explore the Spoke app and describe what you see"
    run(goal)
