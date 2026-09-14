package tui

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
)

func TestRequestRoundTripPreservesDataAndBounds(t *testing.T) {
	want := syntheticRequest()
	want.Rows[0].Risk = "WARN"

	var wire bytes.Buffer
	if err := NewEncoder(&wire).WriteRequest(want); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(wire.String(), "broker one") || strings.Contains(wire.String(), "$billing") {
		t.Fatal("arbitrary display fields must be encoded on the wire")
	}
	got, err := NewDecoder(&wire).ReadRequest()
	if err != nil {
		t.Fatal(err)
	}
	if got.Header != want.Header || got.Subtitle != want.Subtitle || got.Initial != want.Initial {
		t.Fatalf("request metadata changed: %#v", got)
	}
	if got.Rows[0] != want.Rows[0] || got.Rows[1] != want.Rows[1] {
		t.Fatalf("row data changed:\n got %#v\nwant %#v", got.Rows, want.Rows)
	}
}

func TestDetailAndResultRecordsAreExact(t *testing.T) {
	var helperOutput bytes.Buffer
	helperEncoder := NewEncoder(&helperOutput)
	if err := helperEncoder.WriteDetailRequest(7, 1); err != nil {
		t.Fatal(err)
	}
	if err := helperEncoder.WriteResult(ActionEdit, 1); err != nil {
		t.Fatal(err)
	}
	want := "BGTUI\t1\tDETAIL\t7\t1\nBGTUI\t1\tRESULT\tEDIT\t1\n"
	if helperOutput.String() != want {
		t.Fatalf("helper output:\n%q\nwant:\n%q", helperOutput.String(), want)
	}

	var shellReply bytes.Buffer
	if err := NewEncoder(&shellReply).WriteDetailResponse(DetailResponse{
		RequestID: 7,
		Index:     1,
		OK:        true,
		Detail:    `printf '%s' '$HOME; not syntax'`,
	}); err != nil {
		t.Fatal(err)
	}
	response, err := NewDecoder(&shellReply).ReadDetailResponse(7, 1)
	if err != nil {
		t.Fatal(err)
	}
	if !response.OK || response.Detail != `printf '%s' '$HOME; not syntax'` {
		t.Fatalf("detail response changed: %#v", response)
	}
}

func TestProtocolRejectsMalformedOrUnsafeInput(t *testing.T) {
	encoded := func(value string) string {
		return base64.StdEncoding.EncodeToString([]byte(value))
	}
	validStart := fmt.Sprintf("BGTUI\t1\tSTART\t0\t1\t%s\t%s\n", encoded("HEADER"), encoded("subtitle"))
	validRow := fmt.Sprintf("BGTUI\t1\tROW\t0\t1\t1\t%s\t%s\t%s\t%s\n", encoded("Title"), encoded(""), encoded(""), encoded("command"))
	validReady := "BGTUI\t1\tREADY\n"

	tests := map[string]string{
		"unsupported version": strings.Replace(validStart, "BGTUI\t1", "BGTUI\t2", 1) + validRow + validReady,
		"unexpected eof":      validStart + validRow,
		"invalid base64":      "BGTUI\t1\tSTART\t0\t1\t%%%\t\n" + validRow + validReady,
		"control character":   fmt.Sprintf("BGTUI\t1\tSTART\t0\t1\t%s\t\n", encoded("BAD\x1b[2J")) + validRow + validReady,
		"wrong row index":     validStart + strings.Replace(validRow, "\tROW\t0\t", "\tROW\t1\t", 1) + validReady,
	}
	for name, input := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := NewDecoder(strings.NewReader(input)).ReadRequest(); err == nil {
				t.Fatal("malformed input was accepted")
			}
		})
	}
}

func TestProtocolRejectsOversizedFieldsAndInvalidResults(t *testing.T) {
	request := syntheticRequest()
	request.Header = strings.Repeat("x", MaxDecodedFieldBytes+1)
	if err := NewEncoder(&bytes.Buffer{}).WriteRequest(request); err == nil {
		t.Fatal("oversized field was accepted")
	}
	encoder := NewEncoder(&bytes.Buffer{})
	if err := encoder.WriteResult(ActionRun, -1); err == nil {
		t.Fatal("RUN without an index was accepted")
	}
	if err := encoder.WriteResult(ActionCancel, 0); err == nil {
		t.Fatal("CANCEL with an index was accepted")
	}
}
