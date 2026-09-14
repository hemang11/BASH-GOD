package tui

import (
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"sync/atomic"

	tea "charm.land/bubbletea/v2"
)

type protocolBridge struct {
	decoder *Decoder
	encoder *Encoder
	serial  sync.Mutex
	nextID  atomic.Uint64
}

func (b *protocolBridge) loadDetail(index int) tea.Cmd {
	return func() tea.Msg {
		// The shell side resolves details synchronously. Serialize each complete
		// request/response pair so one decoder owns the input stream and a rapid
		// key sequence cannot associate a response with the wrong row.
		b.serial.Lock()
		defer b.serial.Unlock()

		requestID := b.nextID.Add(1)
		if err := b.encoder.WriteDetailRequest(requestID, index); err != nil {
			return DetailLoadedMsg{Index: index, Fatal: err}
		}
		response, err := b.decoder.ReadDetailResponse(requestID, index)
		if err != nil {
			return DetailLoadedMsg{Index: index, Fatal: err}
		}
		if !response.OK {
			return DetailLoadedMsg{Index: index, Reason: response.Reason}
		}
		return DetailLoadedMsg{Index: index, Detail: response.Detail}
	}
}

func Run(protocolInput io.Reader, protocolOutput io.Writer, diagnostics io.Writer) int {
	decoder := NewDecoder(protocolInput)
	request, err := decoder.ReadRequest()
	if err != nil {
		fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", err)
		return ExitProtocol
	}

	ttyInput, ttyOutput, err := tea.OpenTTY()
	if err != nil {
		fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", err)
		return ExitTerminal
	}
	defer ttyInput.Close()
	defer ttyOutput.Close()

	encoder := NewEncoder(protocolOutput)
	bridge := &protocolBridge{decoder: decoder, encoder: encoder}
	model := NewModel(request, bridge.loadDetail)
	program := tea.NewProgram(
		model,
		tea.WithInput(ttyInput),
		tea.WithOutput(ttyOutput),
		tea.WithEnvironment(os.Environ()),
	)

	finalModel, err := program.Run()
	return finishProgram(encoder, finalModel, err, diagnostics)
}

// finishProgram translates the terminal library's final state into the
// protocol-owned result. Bubble Tea handles a process-level SIGINT before it
// calls Model.Update, so treat that separately from ordinary terminal errors:
// the parent must receive a cancellation before the helper exits 130.
func finishProgram(encoder *Encoder, finalModel tea.Model, runErr error, diagnostics io.Writer) int {
	if errors.Is(runErr, tea.ErrInterrupted) {
		if err := encoder.WriteResult(ActionCancel, -1); err != nil {
			fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", err)
			return ExitProtocol
		}
		return ExitInterrupt
	}
	if runErr != nil {
		fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", runErr)
		return ExitTerminal
	}
	result, ok := finalModel.(*Model)
	if !ok {
		fmt.Fprintln(diagnostics, "BASH_GOD TUI: picker returned an unexpected model")
		return ExitTerminal
	}
	action, index, interrupted, fatal := result.Result()
	if fatal != nil {
		fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", fatal)
		return ExitTerminal
	}
	if action == ActionNone {
		action = ActionCancel
		index = -1
	}
	if err := encoder.WriteResult(action, index); err != nil {
		fmt.Fprintf(diagnostics, "BASH_GOD TUI: %v\n", err)
		return ExitProtocol
	}
	if interrupted {
		return ExitInterrupt
	}
	return ExitOK
}
