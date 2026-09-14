package tui

import (
	"errors"
	"fmt"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"
)

const (
	minimumWidth       = 40
	minimumHeight      = 18
	maximumBoxWidth    = 74
	maximumVisibleRows = 9
)

var errUnsupportedTerminal = errors.New("terminal is too small for the inline picker")

type DetailLoadedMsg struct {
	Index  int
	Detail string
	Reason string
	Fatal  error
}

type DetailLoader func(index int) tea.Cmd

type Model struct {
	header        string
	subtitle      string
	rows          []Row
	selected      int
	width         int
	height        int
	action        Action
	interrupted   bool
	fatal         error
	visibleDetail string
	loadDetail    DetailLoader
	detailLoading []bool
	pendingAction Action
	theme         theme
}

type theme struct {
	topLeft     string
	topRight    string
	bottomLeft  string
	bottomRight string
	vertical    string
	horizontal  string
	marker      string
	reset       string
	bold        string
	dim         string
	brand       string
	accent      string
	command     string
	warning     string
}

func themeFromEnvironment() theme {
	t := theme{
		topLeft: "╭", topRight: "╮", bottomLeft: "╰", bottomRight: "╯",
		vertical: "│", horizontal: "─", marker: "❯",
	}
	locale := strings.ToUpper(firstNonEmpty(os.Getenv("LC_ALL"), os.Getenv("LC_CTYPE"), os.Getenv("LANG")))
	if !strings.Contains(locale, "UTF-8") && !strings.Contains(locale, "UTF8") {
		t.topLeft, t.topRight, t.bottomLeft, t.bottomRight = "+", "+", "+", "+"
		t.vertical, t.horizontal, t.marker = "|", "-", ">"
	}

	_, noColor := os.LookupEnv("NO_COLOR")
	colorMode := strings.ToLower(os.Getenv("GOD_COLOR"))
	if colorMode == "" {
		colorMode = "auto"
	}
	colorEnabled := !noColor && colorMode != "never" && os.Getenv("TERM") != "dumb"
	if colorEnabled {
		t.reset = "\x1b[0m"
		t.bold = "\x1b[1m"
		t.dim = "\x1b[2m"
		t.brand = "\x1b[1;35m"
		t.accent = "\x1b[1;36m"
		t.command = "\x1b[32m"
		t.warning = "\x1b[1;33m"
	}
	return t
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func NewModel(request Request, loadDetail DetailLoader) *Model {
	rows := append([]Row(nil), request.Rows...)
	detailLoading := make([]bool, len(rows))
	for index, row := range rows {
		detailLoading[index] = row.DetailKnown
	}
	return &Model{
		header:        request.Header,
		subtitle:      request.Subtitle,
		rows:          rows,
		selected:      request.Initial,
		width:         80,
		visibleDetail: rows[request.Initial].Detail,
		loadDetail:    loadDetail,
		detailLoading: detailLoading,
		theme:         themeFromEnvironment(),
	}
}

func (m *Model) Init() tea.Cmd { return nil }

func (m *Model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch message := message.(type) {
	case tea.WindowSizeMsg:
		if message.Width < minimumWidth || message.Height < minimumHeight {
			m.fatal = errUnsupportedTerminal
			m.action = ActionCancel
			return m, tea.Quit
		}
		m.width = message.Width
		m.height = message.Height
	case DetailLoadedMsg:
		if message.Fatal != nil {
			m.fatal = message.Fatal
			m.action = ActionCancel
			return m, tea.Quit
		}
		if message.Index < 0 || message.Index >= len(m.rows) {
			m.fatal = fmt.Errorf("detail index %d is outside the row set", message.Index)
			m.action = ActionCancel
			return m, tea.Quit
		}
		row := &m.rows[message.Index]
		m.detailLoading[message.Index] = true
		if message.Reason != "" {
			row.Runnable = false
			row.Compatibility = message.Reason
			row.Detail = message.Reason
		} else {
			row.Detail = message.Detail
		}
		row.DetailKnown = true
		if message.Index == m.selected {
			m.visibleDetail = row.Detail
			if m.pendingAction != ActionNone {
				pending := m.pendingAction
				m.pendingAction = ActionNone
				if m.selectedReady() {
					m.action = pending
					return m, tea.Quit
				}
			}
		}
	case tea.KeyPressMsg:
		switch message.String() {
		case "up", "k":
			return m.move(-1)
		case "down", "j":
			return m.move(1)
		case "1", "2", "3", "4", "5", "6", "7", "8", "9":
			return m.moveTo(int(message.String()[0] - '1'))
		case "enter":
			if m.selectedReady() {
				m.action = ActionRun
				return m, tea.Quit
			}
			m.deferSelectedAction(ActionRun)
		case "e":
			if m.selectedReady() {
				m.action = ActionEdit
				return m, tea.Quit
			}
			m.deferSelectedAction(ActionEdit)
		case "esc", "q":
			m.action = ActionCancel
			return m, tea.Quit
		case "ctrl+c":
			m.action = ActionCancel
			m.interrupted = true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m *Model) View() tea.View {
	width := m.width
	if width < minimumWidth {
		width = minimumWidth
	}
	boxWidth := width
	if boxWidth > maximumBoxWidth {
		boxWidth = maximumBoxWidth
	}
	commandWidth := width - 6
	if commandWidth < 20 {
		commandWidth = 20
	}

	var rendered strings.Builder
	rendered.WriteString(m.theme.brand + m.theme.topLeft + strings.Repeat(m.theme.horizontal, boxWidth-2) + m.theme.topRight + m.theme.reset + "\n")
	rendered.WriteString(boxLine(m.header, boxWidth, m.theme.bold, m.theme))
	if m.subtitle != "" {
		rendered.WriteString(boxLine(m.subtitle, boxWidth, m.theme.dim, m.theme))
	}
	rendered.WriteString(m.theme.brand + m.theme.bottomLeft + strings.Repeat(m.theme.horizontal, boxWidth-2) + m.theme.bottomRight + m.theme.reset + "\n\n")

	start, end := m.visibleRange()
	for index := start; index < end; index++ {
		row := m.rows[index]
		marker := "    "
		markerStyle := m.theme.dim
		titleStyle := m.theme.dim
		if index == m.selected {
			marker = "  " + m.theme.marker + " "
			markerStyle = m.theme.accent
			titleStyle = m.theme.accent
			if row.Compatibility != "" || row.Risk != "" {
				markerStyle = m.theme.warning
			}
		}
		rendered.WriteString(markerStyle + marker + m.theme.reset + renderRowLabel(row, width-6, titleStyle, m.theme) + "\n")
	}

	if len(m.rows) > 0 {
		rendered.WriteString("\n  " + renderRowLabel(m.rows[m.selected], width-4, m.theme.accent, m.theme) + "\n")
		wrapped := ansi.Hardwrap(m.visibleDetail, commandWidth, false)
		for index, line := range strings.Split(wrapped, "\n") {
			prefix := "    " + m.theme.command
			if index == 0 {
				prefix = "  " + m.theme.command + "$ "
			}
			rendered.WriteString(prefix + line + m.theme.reset + "\n")
		}
	}
	rendered.WriteString("  " + m.theme.dim + ansi.Truncate("↑/↓ move · e edit · enter run · esc cancel", width-4, "…") + m.theme.reset + "\n")

	view := tea.NewView(rendered.String())
	view.AltScreen = false
	return view
}

func renderRowLabel(row Row, width int, titleStyle string, t theme) string {
	if width < 1 {
		return ""
	}
	suffix := ""
	if row.Compatibility != "" {
		suffix += " [" + row.Compatibility + "]"
	}
	if row.Risk != "" {
		suffix += " [" + row.Risk + "]"
	}
	maxSuffixWidth := width - 12
	if maxSuffixWidth < 0 {
		maxSuffixWidth = 0
	}
	if ansi.StringWidth(suffix) > maxSuffixWidth {
		suffix = ansi.Truncate(suffix, maxSuffixWidth, "…")
	}
	titleWidth := width - ansi.StringWidth(suffix)
	if titleWidth < 1 {
		titleWidth = 1
	}
	title := ansi.Truncate(row.Title, titleWidth, "…")
	return titleStyle + title + t.reset + t.warning + suffix + t.reset
}

func (m *Model) Result() (Action, int, bool, error) {
	index := m.selected
	if m.action == ActionCancel {
		index = -1
	}
	return m.action, index, m.interrupted, m.fatal
}

func (m *Model) move(delta int) (tea.Model, tea.Cmd) {
	return m.moveTo(m.selected + delta)
}

func (m *Model) moveTo(index int) (tea.Model, tea.Cmd) {
	if index < 0 || index >= len(m.rows) || index == m.selected {
		return m, nil
	}
	m.selected = index
	m.pendingAction = ActionNone
	if m.rows[index].DetailKnown {
		m.visibleDetail = m.rows[index].Detail
		return m, nil
	}
	if m.loadDetail == nil || m.detailLoading[index] {
		return m, nil
	}
	m.detailLoading[index] = true
	return m, m.loadDetail(index)
}

// deferSelectedAction remembers an explicit Enter/edit request only while the
// selected row's already-reviewed detail is being loaded. It never turns an
// unresolved row into a runnable one: a failed or blocked detail response
// clears the intent without returning a result.
func (m *Model) deferSelectedAction(action Action) {
	if len(m.rows) == 0 || m.rows[m.selected].DetailKnown || !m.detailLoading[m.selected] {
		return
	}
	m.pendingAction = action
}

func (m *Model) selectedReady() bool {
	return len(m.rows) > 0 && m.rows[m.selected].Runnable && m.rows[m.selected].DetailKnown
}

func (m *Model) visibleRange() (int, int) {
	if len(m.rows) <= maximumVisibleRows {
		return 0, len(m.rows)
	}
	start := m.selected - maximumVisibleRows/2
	if start < 0 {
		start = 0
	}
	end := start + maximumVisibleRows
	if end > len(m.rows) {
		end = len(m.rows)
		start = end - maximumVisibleRows
	}
	return start, end
}

func boxLine(text string, width int, style string, t theme) string {
	text = ansi.Truncate(text, width-4, "…")
	padding := width - 3 - ansi.StringWidth(text)
	if padding < 1 {
		padding = 1
	}
	return fmt.Sprintf("%s%s%s %s%s%s%s%s%s\n", t.brand, t.vertical, t.reset, style, text, t.reset, strings.Repeat(" ", padding), t.brand+t.vertical, t.reset)
}
