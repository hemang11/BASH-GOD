package tui

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestRunRejectsProtocolBeforeOpeningTerminal(t *testing.T) {
	var output bytes.Buffer
	var diagnostics bytes.Buffer

	status := Run(strings.NewReader("BGTUI\t99\tSTART\t0\t1\tSEVBREVS\t\n"), &output, &diagnostics)

	if status != ExitProtocol {
		t.Fatalf("Run returned status %d; want %d", status, ExitProtocol)
	}
	if output.Len() != 0 {
		t.Fatalf("invalid input produced protocol output %q", output.String())
	}
	if !strings.Contains(diagnostics.String(), "unsupported protocol version") {
		t.Fatalf("diagnostic did not explain the failure: %q", diagnostics.String())
	}
}

func TestFinishProgramMapsProcessInterruptToCancellation(t *testing.T) {
	var output bytes.Buffer
	var diagnostics bytes.Buffer
	status := finishProgram(NewEncoder(&output), NewModel(syntheticRequest(), nil), tea.ErrInterrupted, &diagnostics)
	if status != ExitInterrupt {
		t.Fatalf("interrupt status=%d want=%d", status, ExitInterrupt)
	}
	if output.String() != "BGTUI\t1\tRESULT\tCANCEL\t-1\n" {
		t.Fatalf("interrupt did not send cancellation: %q", output.String())
	}
	if diagnostics.Len() != 0 {
		t.Fatalf("interrupt should not be a terminal diagnostic: %q", diagnostics.String())
	}
}

func TestFinishProgramTreatsEOFAndTerminalFailureAsNonExecutingErrors(t *testing.T) {
	for name, runErr := range map[string]error{
		"unexpected eof":   io.ErrUnexpectedEOF,
		"terminal failure": errors.New("terminal disappeared"),
	} {
		t.Run(name, func(t *testing.T) {
			var output bytes.Buffer
			var diagnostics bytes.Buffer
			status := finishProgram(NewEncoder(&output), NewModel(syntheticRequest(), nil), runErr, &diagnostics)
			if status != ExitTerminal || output.Len() != 0 || !strings.Contains(diagnostics.String(), runErr.Error()) {
				t.Fatalf("failure status=%d output=%q diagnostics=%q", status, output.String(), diagnostics.String())
			}
		})
	}
}

func TestFinishProgramWritesExactlyOneNormalResult(t *testing.T) {
	model := NewModel(syntheticRequest(), nil)
	updated, quit := model.Update(key(tea.KeyEscape, ""))
	if quit == nil {
		t.Fatal("Escape must end the helper")
	}
	var output bytes.Buffer
	var diagnostics bytes.Buffer
	status := finishProgram(NewEncoder(&output), updated, nil, &diagnostics)
	if status != ExitOK || output.String() != "BGTUI\t1\tRESULT\tCANCEL\t-1\n" || diagnostics.Len() != 0 {
		t.Fatalf("normal cancellation status=%d output=%q diagnostics=%q", status, output.String(), diagnostics.String())
	}
}
