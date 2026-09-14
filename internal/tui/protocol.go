package tui

import (
	"bufio"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
	"unicode"
	"unicode/utf8"
)

const (
	ProtocolName    = "BGTUI"
	ProtocolVersion = 1

	MaxRows              = 256
	MaxDecodedFieldBytes = 64 * 1024
	MaxDecodedInputBytes = 2 * 1024 * 1024
	maxWireRecordBytes   = 1024 * 1024
)

const (
	ExitOK        = 0
	ExitProtocol  = 2
	ExitTerminal  = 3
	ExitInterrupt = 130
)

type Action string

const (
	ActionNone   Action = ""
	ActionRun    Action = "RUN"
	ActionEdit   Action = "EDIT"
	ActionCancel Action = "CANCEL"
)

type Row struct {
	Title         string
	Compatibility string
	Risk          string
	Runnable      bool
	Detail        string
	DetailKnown   bool
}

type Request struct {
	Header   string
	Subtitle string
	Initial  int
	Rows     []Row
}

type DetailResponse struct {
	RequestID uint64
	Index     int
	Detail    string
	Reason    string
	OK        bool
}

type Decoder struct {
	scanner *bufio.Scanner
	total   int
}

func NewDecoder(r io.Reader) *Decoder {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 4096), maxWireRecordBytes)
	return &Decoder{scanner: scanner}
}

func (d *Decoder) ReadRequest() (Request, error) {
	fields, err := d.readRecord()
	if err != nil {
		return Request{}, fmt.Errorf("read START: %w", err)
	}
	if err := requireRecord(fields, "START", 7); err != nil {
		return Request{}, err
	}

	initial, err := parseBoundedInt(fields[3], 0, MaxRows-1, "initial index")
	if err != nil {
		return Request{}, err
	}
	count, err := parseBoundedInt(fields[4], 1, MaxRows, "row count")
	if err != nil {
		return Request{}, err
	}
	if initial >= count {
		return Request{}, fmt.Errorf("initial index %d is outside %d rows", initial, count)
	}
	header, err := d.decodeText(fields[5], "header", true)
	if err != nil {
		return Request{}, err
	}
	subtitle, err := d.decodeText(fields[6], "subtitle", false)
	if err != nil {
		return Request{}, err
	}

	request := Request{Header: header, Subtitle: subtitle, Initial: initial, Rows: make([]Row, 0, count)}
	for index := 0; index < count; index++ {
		fields, err = d.readRecord()
		if err != nil {
			return Request{}, fmt.Errorf("read ROW %d: %w", index, err)
		}
		if err := requireRecord(fields, "ROW", 10); err != nil {
			return Request{}, err
		}
		rowIndex, err := parseBoundedInt(fields[3], 0, count-1, "row index")
		if err != nil {
			return Request{}, err
		}
		if rowIndex != index {
			return Request{}, fmt.Errorf("row index %d is out of order; expected %d", rowIndex, index)
		}
		runnable, err := parseBool(fields[4], "runnable")
		if err != nil {
			return Request{}, err
		}
		detailKnown, err := parseBool(fields[5], "detail-known")
		if err != nil {
			return Request{}, err
		}
		title, err := d.decodeText(fields[6], "row title", true)
		if err != nil {
			return Request{}, err
		}
		compatibility, err := d.decodeText(fields[7], "compatibility", false)
		if err != nil {
			return Request{}, err
		}
		risk, err := d.decodeText(fields[8], "risk", false)
		if err != nil {
			return Request{}, err
		}
		if risk != "" && risk != "WRITE" && risk != "WARN" && risk != "DELETE" {
			return Request{}, fmt.Errorf("unsupported risk %q", risk)
		}
		detail, err := d.decodeText(fields[9], "detail", detailKnown)
		if err != nil {
			return Request{}, err
		}
		if !detailKnown && detail != "" {
			return Request{}, errors.New("unknown detail must have an empty payload")
		}
		request.Rows = append(request.Rows, Row{
			Title: title, Compatibility: compatibility, Risk: risk, Runnable: runnable,
			Detail: detail, DetailKnown: detailKnown,
		})
	}

	fields, err = d.readRecord()
	if err != nil {
		return Request{}, fmt.Errorf("read READY: %w", err)
	}
	if err := requireRecord(fields, "READY", 3); err != nil {
		return Request{}, err
	}
	if !request.Rows[request.Initial].DetailKnown {
		return Request{}, errors.New("the initially selected row must include its resolved detail")
	}
	return request, nil
}

func (d *Decoder) ReadDetailResponse(requestID uint64, index int) (DetailResponse, error) {
	fields, err := d.readRecord()
	if err != nil {
		return DetailResponse{}, fmt.Errorf("read DETAIL_RESULT: %w", err)
	}
	if err := requireRecord(fields, "DETAIL_RESULT", 8); err != nil {
		return DetailResponse{}, err
	}
	gotRequestID, err := strconv.ParseUint(fields[3], 10, 64)
	if err != nil || gotRequestID == 0 {
		return DetailResponse{}, fmt.Errorf("invalid detail request id %q", fields[3])
	}
	gotIndex, err := parseBoundedInt(fields[4], 0, MaxRows-1, "detail index")
	if err != nil {
		return DetailResponse{}, err
	}
	if gotRequestID != requestID || gotIndex != index {
		return DetailResponse{}, fmt.Errorf(
			"detail response %d/%d does not match request %d/%d",
			gotRequestID, gotIndex, requestID, index,
		)
	}
	status := fields[5]
	detail, err := d.decodeText(fields[6], "detail response", status == "OK")
	if err != nil {
		return DetailResponse{}, err
	}
	reason, err := d.decodeText(fields[7], "detail reason", status == "ERROR")
	if err != nil {
		return DetailResponse{}, err
	}
	response := DetailResponse{RequestID: requestID, Index: index}
	switch status {
	case "OK":
		if reason != "" {
			return DetailResponse{}, errors.New("successful detail response cannot include a reason")
		}
		response.OK = true
		response.Detail = detail
	case "ERROR":
		if detail != "" {
			return DetailResponse{}, errors.New("failed detail response cannot include a detail")
		}
		response.Reason = reason
	default:
		return DetailResponse{}, fmt.Errorf("unsupported detail status %q", status)
	}
	return response, nil
}

func (d *Decoder) readRecord() ([]string, error) {
	if !d.scanner.Scan() {
		if err := d.scanner.Err(); err != nil {
			return nil, err
		}
		return nil, io.ErrUnexpectedEOF
	}
	return strings.Split(d.scanner.Text(), "\t"), nil
}

func (d *Decoder) decodeText(encoded, name string, required bool) (string, error) {
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", fmt.Errorf("%s is not valid base64", name)
	}
	if len(decoded) > MaxDecodedFieldBytes {
		return "", fmt.Errorf("%s exceeds %d decoded bytes", name, MaxDecodedFieldBytes)
	}
	d.total += len(decoded)
	if d.total > MaxDecodedInputBytes {
		return "", fmt.Errorf("request exceeds %d decoded bytes", MaxDecodedInputBytes)
	}
	value := string(decoded)
	if required && value == "" {
		return "", fmt.Errorf("%s is required", name)
	}
	if !utf8.ValidString(value) {
		return "", fmt.Errorf("%s is not valid UTF-8", name)
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return "", fmt.Errorf("%s contains a control character", name)
		}
	}
	return value, nil
}

type Encoder struct {
	mu sync.Mutex
	w  *bufio.Writer
}

func NewEncoder(w io.Writer) *Encoder {
	return &Encoder{w: bufio.NewWriter(w)}
}

func (e *Encoder) WriteRequest(request Request) error {
	if err := validateRequest(request); err != nil {
		return err
	}
	e.mu.Lock()
	defer e.mu.Unlock()

	if err := e.writeRecord(
		ProtocolName, strconv.Itoa(ProtocolVersion), "START",
		strconv.Itoa(request.Initial), strconv.Itoa(len(request.Rows)),
		encodeText(request.Header), encodeText(request.Subtitle),
	); err != nil {
		return err
	}
	for index, row := range request.Rows {
		if err := e.writeRecord(
			ProtocolName, strconv.Itoa(ProtocolVersion), "ROW", strconv.Itoa(index),
			formatBool(row.Runnable), formatBool(row.DetailKnown), encodeText(row.Title),
			encodeText(row.Compatibility), encodeText(row.Risk), encodeText(row.Detail),
		); err != nil {
			return err
		}
	}
	if err := e.writeRecord(ProtocolName, strconv.Itoa(ProtocolVersion), "READY"); err != nil {
		return err
	}
	return e.w.Flush()
}

func (e *Encoder) WriteDetailRequest(requestID uint64, index int) error {
	if requestID == 0 || index < 0 || index >= MaxRows {
		return errors.New("invalid detail request")
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if err := e.writeRecord(
		ProtocolName, strconv.Itoa(ProtocolVersion), "DETAIL",
		strconv.FormatUint(requestID, 10), strconv.Itoa(index),
	); err != nil {
		return err
	}
	return e.w.Flush()
}

func (e *Encoder) WriteDetailResponse(response DetailResponse) error {
	if response.RequestID == 0 || response.Index < 0 || response.Index >= MaxRows {
		return errors.New("invalid detail response")
	}
	status := "ERROR"
	if response.OK {
		status = "OK"
	}
	if response.OK && (response.Detail == "" || response.Reason != "") {
		return errors.New("successful detail response requires only a detail")
	}
	if !response.OK && (response.Reason == "" || response.Detail != "") {
		return errors.New("failed detail response requires only a reason")
	}
	if err := validateText(response.Detail, "detail", response.OK); err != nil {
		return err
	}
	if err := validateText(response.Reason, "detail reason", !response.OK); err != nil {
		return err
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if err := e.writeRecord(
		ProtocolName, strconv.Itoa(ProtocolVersion), "DETAIL_RESULT",
		strconv.FormatUint(response.RequestID, 10), strconv.Itoa(response.Index), status,
		encodeText(response.Detail), encodeText(response.Reason),
	); err != nil {
		return err
	}
	return e.w.Flush()
}

func (e *Encoder) WriteResult(action Action, index int) error {
	switch action {
	case ActionRun, ActionEdit:
		if index < 0 || index >= MaxRows {
			return errors.New("run/edit result requires a valid index")
		}
	case ActionCancel:
		if index != -1 {
			return errors.New("cancel result requires index -1")
		}
	default:
		return fmt.Errorf("unsupported result action %q", action)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if err := e.writeRecord(
		ProtocolName, strconv.Itoa(ProtocolVersion), "RESULT", string(action), strconv.Itoa(index),
	); err != nil {
		return err
	}
	return e.w.Flush()
}

func (e *Encoder) writeRecord(fields ...string) error {
	_, err := fmt.Fprintln(e.w, strings.Join(fields, "\t"))
	return err
}

func requireRecord(fields []string, kind string, count int) error {
	if len(fields) != count {
		return fmt.Errorf("%s record has %d fields; expected %d", kind, len(fields), count)
	}
	if fields[0] != ProtocolName {
		return fmt.Errorf("unsupported protocol %q", fields[0])
	}
	if fields[1] != strconv.Itoa(ProtocolVersion) {
		return fmt.Errorf("unsupported protocol version %q", fields[1])
	}
	if fields[2] != kind {
		return fmt.Errorf("expected %s record, received %q", kind, fields[2])
	}
	return nil
}

func parseBoundedInt(value string, minimum, maximum int, name string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < minimum || parsed > maximum {
		return 0, fmt.Errorf("invalid %s %q", name, value)
	}
	return parsed, nil
}

func parseBool(value, name string) (bool, error) {
	switch value {
	case "0":
		return false, nil
	case "1":
		return true, nil
	default:
		return false, fmt.Errorf("invalid %s %q", name, value)
	}
}

func formatBool(value bool) string {
	if value {
		return "1"
	}
	return "0"
}

func encodeText(value string) string {
	return base64.StdEncoding.EncodeToString([]byte(value))
}

func validateRequest(request Request) error {
	if len(request.Rows) < 1 || len(request.Rows) > MaxRows {
		return fmt.Errorf("row count must be between 1 and %d", MaxRows)
	}
	if request.Initial < 0 || request.Initial >= len(request.Rows) {
		return errors.New("initial index is outside the row set")
	}
	if err := validateText(request.Header, "header", true); err != nil {
		return err
	}
	if err := validateText(request.Subtitle, "subtitle", false); err != nil {
		return err
	}
	total := len(request.Header) + len(request.Subtitle)
	for index, row := range request.Rows {
		if err := validateText(row.Title, fmt.Sprintf("row %d title", index), true); err != nil {
			return err
		}
		if err := validateText(row.Compatibility, fmt.Sprintf("row %d compatibility", index), false); err != nil {
			return err
		}
		if err := validateText(row.Risk, fmt.Sprintf("row %d risk", index), false); err != nil {
			return err
		}
		if row.Risk != "" && row.Risk != "WRITE" && row.Risk != "WARN" && row.Risk != "DELETE" {
			return fmt.Errorf("unsupported risk %q", row.Risk)
		}
		if err := validateText(row.Detail, fmt.Sprintf("row %d detail", index), row.DetailKnown); err != nil {
			return err
		}
		if !row.DetailKnown && row.Detail != "" {
			return fmt.Errorf("row %d has an unknown detail with a payload", index)
		}
		total += len(row.Title) + len(row.Compatibility) + len(row.Risk) + len(row.Detail)
	}
	if !request.Rows[request.Initial].DetailKnown {
		return errors.New("the initially selected row must include its resolved detail")
	}
	if total > MaxDecodedInputBytes {
		return fmt.Errorf("request exceeds %d decoded bytes", MaxDecodedInputBytes)
	}
	return nil
}

func validateText(value, name string, required bool) error {
	if required && value == "" {
		return fmt.Errorf("%s is required", name)
	}
	if len(value) > MaxDecodedFieldBytes {
		return fmt.Errorf("%s exceeds %d decoded bytes", name, MaxDecodedFieldBytes)
	}
	if !utf8.ValidString(value) {
		return fmt.Errorf("%s is not valid UTF-8", name)
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return fmt.Errorf("%s contains a control character", name)
		}
	}
	return nil
}
