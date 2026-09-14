package tui

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"
)

func syntheticRequest() Request {
	return Request{
		Header:   "KAFKA SEARCH RESULTS",
		Subtitle: "Smart search: get all consumers",
		Initial:  0,
		Rows: []Row{
			{
				Title:       "List consumer groups",
				Runnable:    true,
				DetailKnown: true,
				Detail:      `/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server "broker one:9092" --group '$billing' --describe`,
			},
			{
				Title:         "Show exact offset",
				Compatibility: "needs v3.0+ (have v1.1.0)",
				Runnable:      true,
			},
			{
				Title:         "Unavailable operation",
				Compatibility: "missing tool",
				Runnable:      false,
				DetailKnown:   true,
				Detail:        "missing-command --flag",
			},
		},
	}
}

func key(code rune, text string) tea.KeyPressMsg {
	return tea.KeyPressMsg(tea.Key{Code: code, Text: text})
}

func TestViewIsInlineAndWrapsLiteralCommandData(t *testing.T) {
	t.Setenv("GOD_COLOR", "never")
	model := NewModel(syntheticRequest(), nil)
	model.width = 48
	view := model.View()
	if view.AltScreen {
		t.Fatal("picker must stay in the normal terminal buffer")
	}
	if !strings.Contains(view.Content, "broker one:9092") || !strings.Contains(view.Content, "'$billing'") {
		t.Fatalf("command data changed in view: %q", view.Content)
	}
	for _, line := range strings.Split(view.Content, "\n") {
		if width := ansi.StringWidth(line); width > 48 {
			t.Fatalf("line width %d exceeds terminal width: %q", width, line)
		}
	}
}

func TestViewUsesBashGodThemeAndMargins(t *testing.T) {
	oldNoColor, hadNoColor := os.LookupEnv("NO_COLOR")
	if err := os.Unsetenv("NO_COLOR"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if hadNoColor {
			_ = os.Setenv("NO_COLOR", oldNoColor)
		} else {
			_ = os.Unsetenv("NO_COLOR")
		}
	})
	t.Setenv("GOD_COLOR", "always")
	t.Setenv("LC_ALL", "en_US.UTF-8")
	t.Setenv("TERM", "xterm-256color")
	model := NewModel(syntheticRequest(), nil)
	view := model.View().Content
	if !strings.Contains(view, "\x1b[1;35m╭") || !strings.Contains(view, "\x1b[32m$ /opt/kafka") {
		t.Fatalf("brand or command theme is missing: %q", view)
	}
	plain := ansi.Strip(view)
	if !strings.Contains(plain, "\n  ❯ List consumer groups") ||
		!strings.Contains(plain, "\n  List consumer groups\n  $ /opt/kafka") ||
		!strings.Contains(plain, "\n  ↑/↓ move") {
		t.Fatalf("picker margins changed: %q", plain)
	}
}

func TestCompatibilityStaysAdjacentInListAndDetail(t *testing.T) {
	t.Setenv("GOD_COLOR", "never")
	request := syntheticRequest()
	request.Initial = 1
	request.Rows[1].DetailKnown = true
	request.Rows[1].Detail = "kafka-get-offsets.sh --help"
	model := NewModel(request, nil)
	view := model.View().Content
	want := "Show exact offset [needs v3.0+ (have v1.1.0)]"
	if strings.Count(view, want) != 2 {
		t.Fatalf("compatibility was not adjacent in list and detail: %q", view)
	}
}

func TestViewUsesAsciiFallback(t *testing.T) {
	t.Setenv("GOD_COLOR", "never")
	t.Setenv("LC_ALL", "C")
	model := NewModel(syntheticRequest(), nil)
	view := model.View().Content
	if !strings.HasPrefix(view, "+") || strings.ContainsAny(view, "╭╮╰╯│─❯") {
		t.Fatalf("ASCII fallback contains Unicode terminal glyphs: %q", view)
	}
}

func TestSmallTerminalQuitsForStaticFallback(t *testing.T) {
	model := NewModel(syntheticRequest(), nil)
	updated, command := model.Update(tea.WindowSizeMsg{Width: minimumWidth - 1, Height: minimumHeight})
	model = updated.(*Model)
	if command == nil || !errors.Is(model.fatal, errUnsupportedTerminal) {
		t.Fatalf("small terminal did not request fallback: command=%v error=%v", command, model.fatal)
	}
}

func TestLongResultSetScrollsAroundSelection(t *testing.T) {
	request := syntheticRequest()
	request.Rows = nil
	for index := 0; index < 14; index++ {
		request.Rows = append(request.Rows, Row{
			Title:       fmt.Sprintf("Operation %02d", index+1),
			Runnable:    true,
			DetailKnown: true,
			Detail:      fmt.Sprintf("printf operation-%02d", index+1),
		})
	}
	request.Initial = 10
	model := NewModel(request, nil)
	view := ansi.Strip(model.View().Content)
	if strings.Contains(view, "Operation 01") || !strings.Contains(view, "Operation 11") || !strings.Contains(view, "Operation 14") {
		t.Fatalf("long result set did not scroll around selection: %q", view)
	}
}

func TestNavigationLoadsDetailBeforeRun(t *testing.T) {
	var requested int = -1
	loader := func(index int) tea.Cmd {
		requested = index
		return func() tea.Msg {
			return DetailLoadedMsg{
				Index:  index,
				Detail: `curl -sS 'https://host/path?q=two words&literal=$HOME;still-data'`,
			}
		}
	}
	model := NewModel(syntheticRequest(), loader)
	previousDetail := model.visibleDetail

	updated, command := model.Update(key(tea.KeyDown, ""))
	model = updated.(*Model)
	if model.selected != 1 || requested != 1 || command == nil {
		t.Fatalf("down selected=%d requested=%d command=%v", model.selected, requested, command)
	}
	if model.visibleDetail != previousDetail {
		t.Fatal("detail panel changed before the requested detail arrived")
	}

	updated, quit := model.Update(key(tea.KeyEnter, ""))
	model = updated.(*Model)
	if model.action != ActionNone || model.pendingAction != ActionRun || quit != nil {
		t.Fatal("Enter must wait for the unresolved row's reviewed detail")
	}

	updated, quit = model.Update(command())
	model = updated.(*Model)
	if model.visibleDetail != `curl -sS 'https://host/path?q=two words&literal=$HOME;still-data'` || model.action != ActionRun || quit == nil {
		t.Fatalf("resolved deferred Enter did not produce exactly one RUN: detail=%q action=%q quit=%v", model.visibleDetail, model.action, quit)
	}
}

func TestRapidNavigationKeepsOnlyTheCurrentDetailVisibleAndHonorsDeferredRun(t *testing.T) {
	request := syntheticRequest()
	request.Rows[1].DetailKnown = false
	request.Rows[2].Runnable = true
	request.Rows[2].DetailKnown = false
	request.Rows[2].Compatibility = ""

	loads := make([]int, 0, 2)
	loader := func(index int) tea.Cmd {
		loads = append(loads, index)
		return func() tea.Msg {
			return DetailLoadedMsg{Index: index, Detail: fmt.Sprintf("command-%d", index)}
		}
	}
	model := NewModel(request, loader)

	updated, firstLoad := model.Update(key(tea.KeyDown, ""))
	model = updated.(*Model)
	updated, secondLoad := model.Update(key(tea.KeyDown, ""))
	model = updated.(*Model)
	updated, quit := model.Update(key(tea.KeyEnter, ""))
	model = updated.(*Model)
	if quit != nil || model.selected != 2 || model.pendingAction != ActionRun || fmt.Sprint(loads) != "[1 2]" {
		t.Fatalf("rapid selection did not retain its latest deferred intent: selected=%d pending=%q loads=%v quit=%v", model.selected, model.pendingAction, loads, quit)
	}

	updated, quit = model.Update(firstLoad())
	model = updated.(*Model)
	if quit != nil || model.visibleDetail != request.Rows[0].Detail || model.action != ActionNone {
		t.Fatalf("stale detail changed the current selection: detail=%q action=%q quit=%v", model.visibleDetail, model.action, quit)
	}

	updated, quit = model.Update(secondLoad())
	model = updated.(*Model)
	if quit == nil || model.action != ActionRun || model.pendingAction != ActionNone || model.visibleDetail != "command-2" {
		t.Fatalf("current detail did not complete one deferred run: action=%q pending=%q detail=%q quit=%v", model.action, model.pendingAction, model.visibleDetail, quit)
	}
}

func TestRepeatedSelectionDoesNotStartDuplicateDetailLoads(t *testing.T) {
	request := syntheticRequest()
	request.Rows[1].DetailKnown = false
	loads := 0
	model := NewModel(request, func(index int) tea.Cmd {
		loads++
		return func() tea.Msg { return DetailLoadedMsg{Index: index, Detail: "resolved"} }
	})

	updated, first := model.Update(key(tea.KeyDown, ""))
	model = updated.(*Model)
	updated, _ = model.Update(key(tea.KeyUp, ""))
	model = updated.(*Model)
	updated, second := model.Update(key(tea.KeyDown, ""))
	model = updated.(*Model)
	if first == nil || second != nil || loads != 1 {
		t.Fatalf("repeat visit should share one lazy load: first=%v second=%v loads=%d", first, second, loads)
	}

	updated, _ = model.Update(first())
	model = updated.(*Model)
	if !model.rows[1].DetailKnown || model.visibleDetail != "resolved" {
		t.Fatalf("shared lazy load was not applied: %#v", model.rows[1])
	}
}

func TestResizePreservesSelectionAndReflowsTheInlineView(t *testing.T) {
	request := syntheticRequest()
	request.Initial = 1
	request.Rows[1].DetailKnown = true
	request.Rows[1].Detail = strings.Repeat("long-command-part ", 20)
	model := NewModel(request, nil)
	updated, command := model.Update(tea.WindowSizeMsg{Width: 48, Height: 30})
	model = updated.(*Model)
	if command != nil || model.selected != 1 || model.width != 48 || model.height != 30 {
		t.Fatalf("resize changed picker state: selected=%d width=%d height=%d command=%v", model.selected, model.width, model.height, command)
	}
	for _, line := range strings.Split(model.View().Content, "\n") {
		if width := ansi.StringWidth(line); width > 48 {
			t.Fatalf("resize left a line wider than the terminal: %d %q", width, line)
		}
	}
}

func TestEditCancelAndBlockedSelectionAreExplicit(t *testing.T) {
	model := NewModel(syntheticRequest(), nil)
	updated, quit := model.Update(key('e', "e"))
	if updated.(*Model).action != ActionEdit || quit == nil {
		t.Fatal("edit must return an explicit action and quit")
	}

	model = NewModel(syntheticRequest(), nil)
	updated, quit = model.Update(key(tea.KeyEscape, ""))
	if updated.(*Model).action != ActionCancel || quit == nil {
		t.Fatal("Escape must return an explicit cancellation and quit")
	}

	model = NewModel(syntheticRequest(), nil)
	model.selected = 2
	updated, quit = model.Update(key(tea.KeyEnter, ""))
	if updated.(*Model).action != ActionNone || quit != nil {
		t.Fatal("blocked row must ignore Enter")
	}
}

func TestControlCIsAnInterruptedCancellation(t *testing.T) {
	model := NewModel(syntheticRequest(), nil)
	updated, quit := model.Update(tea.KeyPressMsg(tea.Key{Code: 'c', Mod: tea.ModCtrl}))
	model = updated.(*Model)
	if quit == nil {
		t.Fatal("Ctrl-C must quit")
	}
	action, index, interrupted, fatal := model.Result()
	if action != ActionCancel || index != -1 || !interrupted || fatal != nil {
		t.Fatalf("unexpected result: %q %d %t %v", action, index, interrupted, fatal)
	}
}
