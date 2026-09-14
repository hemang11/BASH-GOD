package main

import (
	"fmt"
	"os"

	"github.com/hemang11/BASH-GOD/internal/tui"
)

func main() {
	if len(os.Args) == 2 && os.Args[1] == "--protocol-version" {
		fmt.Println(tui.ProtocolVersion)
		return
	}
	if len(os.Args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: god-tui [--protocol-version]")
		os.Exit(tui.ExitProtocol)
	}

	os.Exit(tui.Run(os.Stdin, os.Stdout, os.Stderr))
}
