//go:build android_e2e

// Package android provides a Go-based adb test harness for driving
// the WingOut Qt app on an Android emulator and verifying its behavior.
package android

import (
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// ADB wraps common adb commands for driving the Android emulator.
type ADB struct {
	Serial     string // e.g. "emulator-5554"
	APKPath    string // path to the APK to install
	PackageID  string // e.g. "com.wingout.app"
	ActivityID string // e.g. ".QtActivity"
}

// NewADB creates a new ADB helper. If serial is empty, uses ANDROID_SERIAL env.
func NewADB(apkPath, packageID string) *ADB {
	serial := os.Getenv("ANDROID_SERIAL")
	if serial == "" {
		serial = "emulator-5554"
	}
	return &ADB{
		Serial:     serial,
		APKPath:    apkPath,
		PackageID:  packageID,
		ActivityID: ".MainActivity",
	}
}

// Run executes an adb command and returns stdout.
func (a *ADB) Run(args ...string) (string, error) {
	cmdArgs := []string{"-s", a.Serial}
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.Command("adb", cmdArgs...)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// Shell runs a command on the device via adb shell.
func (a *ADB) Shell(args ...string) (string, error) {
	cmdArgs := append([]string{"shell"}, args...)
	return a.Run(cmdArgs...)
}

// WaitForBoot waits for the emulator to finish booting.
func (a *ADB) WaitForBoot(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		out, err := a.Shell("getprop", "sys.boot_completed")
		if err == nil && strings.TrimSpace(out) == "1" {
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("emulator did not boot within %s", timeout)
}

// UnlockScreen sends the MENU keyevent to unlock the screen.
func (a *ADB) UnlockScreen() error {
	_, err := a.Shell("input", "keyevent", "82")
	return err
}

// InstallAPK installs the APK onto the device.
func (a *ADB) InstallAPK() error {
	_, err := a.Run("install", "-r", a.APKPath)
	return err
}

// LaunchApp starts the app activity.
func (a *ADB) LaunchApp() error {
	activity := a.PackageID + "/" + a.ActivityID
	_, err := a.Shell("am", "start", "-n", activity)
	return err
}

// StopApp force-stops the app.
func (a *ADB) StopApp() error {
	_, err := a.Shell("am", "force-stop", a.PackageID)
	return err
}

// ClearAppData clears the app's data (fresh state).
func (a *ADB) ClearAppData() error {
	_, err := a.Shell("pm", "clear", a.PackageID)
	return err
}

// Tap sends a tap event at (x, y).
func (a *ADB) Tap(x, y int) error {
	_, err := a.Shell("input", "tap", fmt.Sprint(x), fmt.Sprint(y))
	return err
}

// DoubleTap sends a double-tap at (x, y).
func (a *ADB) DoubleTap(x, y int) error {
	if err := a.Tap(x, y); err != nil {
		return err
	}
	time.Sleep(100 * time.Millisecond)
	return a.Tap(x, y)
}

// LongPress performs a long-press at (x, y) by holding for 1 second.
func (a *ADB) LongPress(x, y int) error {
	return a.Swipe(x, y, x, y, 1000)
}

// Swipe swipes from (x1,y1) to (x2,y2) over durationMs milliseconds.
func (a *ADB) Swipe(x1, y1, x2, y2, durationMs int) error {
	_, err := a.Shell("input", "swipe",
		fmt.Sprint(x1), fmt.Sprint(y1),
		fmt.Sprint(x2), fmt.Sprint(y2),
		fmt.Sprint(durationMs))
	return err
}

// TypeText types text into the focused field.
// Uses `adb shell input text` which sends text through Android's input system.
func (a *ADB) TypeText(text string) error {
	escaped := strings.ReplaceAll(text, " ", "%s")
	if _, err := a.Shell("input", "text", escaped); err != nil {
		return err
	}
	return nil
}

// TypeTextViaKeyEvents types text character-by-character using key events.
// This is more compatible with Qt's TextField on Android than `input text`.
func (a *ADB) TypeTextViaKeyEvents(text string) error {
	for _, ch := range text {
		keycode := charToKeycode(ch)
		if keycode == "" {
			continue
		}
		if _, err := a.Shell("input", "keyevent", keycode); err != nil {
			return err
		}
	}
	return nil
}

// charToKeycode maps a character to its Android KEYCODE string.
func charToKeycode(ch rune) string {
	switch {
	case ch >= 'a' && ch <= 'z':
		return fmt.Sprintf("KEYCODE_%c", ch-32) // KEYCODE_A .. KEYCODE_Z
	case ch >= 'A' && ch <= 'Z':
		return fmt.Sprintf("KEYCODE_%c", ch)
	case ch >= '0' && ch <= '9':
		return fmt.Sprintf("KEYCODE_%c", ch) // KEYCODE_0 .. KEYCODE_9
	case ch == ' ':
		return "KEYCODE_SPACE"
	case ch == '.':
		return "KEYCODE_PERIOD"
	case ch == ',':
		return "KEYCODE_COMMA"
	case ch == '/':
		return "KEYCODE_SLASH"
	case ch == '-':
		return "KEYCODE_MINUS"
	default:
		return ""
	}
}

// PressBack sends the BACK keyevent.
func (a *ADB) PressBack() error {
	_, err := a.Shell("input", "keyevent", "KEYCODE_BACK")
	return err
}

// PressHome sends the HOME keyevent.
func (a *ADB) PressHome() error {
	_, err := a.Shell("input", "keyevent", "KEYCODE_HOME")
	return err
}

// Screenshot captures a screenshot and saves it to localPath.
func (a *ADB) Screenshot(localPath string) error {
	dir := filepath.Dir(localPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	cmd := exec.Command("adb", "-s", a.Serial, "exec-out", "screencap", "-p")
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("screencap: %w", err)
	}
	return os.WriteFile(localPath, out, 0o644)
}

// UINode represents a node in the Android UI hierarchy from uiautomator dump.
type UINode struct {
	XMLName        xml.Name `xml:"node"`
	Class          string   `xml:"class,attr"`
	ContentDesc    string   `xml:"content-desc,attr"`
	Text           string   `xml:"text,attr"`
	ResourceID     string   `xml:"resource-id,attr"`
	Bounds         string   `xml:"bounds,attr"`
	Enabled        string   `xml:"enabled,attr"`
	Clickable      string   `xml:"clickable,attr"`
	Focusable      string   `xml:"focusable,attr"`
	Selected       string   `xml:"selected,attr"`
	Checked        string   `xml:"checked,attr"`
	PackageName    string   `xml:"package,attr"`
	Children       []UINode `xml:"node"`
}

// UIHierarchy is the root of a uiautomator dump.
type UIHierarchy struct {
	XMLName xml.Name `xml:"hierarchy"`
	Nodes   []UINode `xml:"node"`
}

// DumpUI gets the UI hierarchy from the device.
func (a *ADB) DumpUI() (*UIHierarchy, error) {
	devicePath := "/sdcard/ui_dump.xml"
	if _, err := a.Shell("uiautomator", "dump", devicePath); err != nil {
		return nil, fmt.Errorf("uiautomator dump: %w", err)
	}
	out, err := a.Shell("cat", devicePath)
	if err != nil {
		return nil, fmt.Errorf("read dump: %w", err)
	}
	var hierarchy UIHierarchy
	if err := xml.Unmarshal([]byte(out), &hierarchy); err != nil {
		return nil, fmt.Errorf("parse dump: %w", err)
	}
	return &hierarchy, nil
}

// FindByContentDesc searches the UI hierarchy for a node with matching content-desc.
// Content-desc maps to QML Accessible.name.
// Also matches nodes where content-desc starts with "desc," (Qt concatenates
// Accessible.name and Accessible.description with a comma separator).
func (h *UIHierarchy) FindByContentDesc(desc string) *UINode {
	for i := range h.Nodes {
		if n := findNodeByContentDesc(&h.Nodes[i], desc); n != nil {
			return n
		}
	}
	return nil
}

func findNodeByContentDesc(node *UINode, desc string) *UINode {
	if node.ContentDesc == desc || strings.HasPrefix(node.ContentDesc, desc+",") {
		return node
	}
	for i := range node.Children {
		if n := findNodeByContentDesc(&node.Children[i], desc); n != nil {
			return n
		}
	}
	return nil
}

// FindByContentDescPrefix searches for a node whose content-desc starts with the prefix.
// Useful for TextField elements where Qt appends placeholder text to the accessible name.
func (h *UIHierarchy) FindByContentDescPrefix(prefix string) *UINode {
	for i := range h.Nodes {
		if n := findNodeByContentDescPrefix(&h.Nodes[i], prefix); n != nil {
			return n
		}
	}
	return nil
}

func findNodeByContentDescPrefix(node *UINode, prefix string) *UINode {
	if strings.HasPrefix(node.ContentDesc, prefix) {
		return node
	}
	for i := range node.Children {
		if n := findNodeByContentDescPrefix(&node.Children[i], prefix); n != nil {
			return n
		}
	}
	return nil
}

// FindByText searches the UI hierarchy for a node with matching text.
func (h *UIHierarchy) FindByText(text string) *UINode {
	for i := range h.Nodes {
		if n := findNodeByText(&h.Nodes[i], text); n != nil {
			return n
		}
	}
	return nil
}

func findNodeByText(node *UINode, text string) *UINode {
	if node.Text == text {
		return node
	}
	for i := range node.Children {
		if n := findNodeByText(&node.Children[i], text); n != nil {
			return n
		}
	}
	return nil
}

// FindAllByContentDesc finds all nodes matching a content-desc.
func (h *UIHierarchy) FindAllByContentDesc(desc string) []*UINode {
	var results []*UINode
	for i := range h.Nodes {
		collectByContentDesc(&h.Nodes[i], desc, &results)
	}
	return results
}

func collectByContentDesc(node *UINode, desc string, results *[]*UINode) {
	if node.ContentDesc == desc || strings.HasPrefix(node.ContentDesc, desc+",") {
		*results = append(*results, node)
	}
	for i := range node.Children {
		collectByContentDesc(&node.Children[i], desc, results)
	}
}

// FindContainingText finds nodes whose text contains the substring.
func (h *UIHierarchy) FindContainingText(substr string) []*UINode {
	var results []*UINode
	for i := range h.Nodes {
		collectContainingText(&h.Nodes[i], substr, &results)
	}
	return results
}

func collectContainingText(node *UINode, substr string, results *[]*UINode) {
	if strings.Contains(node.Text, substr) || strings.Contains(node.ContentDesc, substr) {
		*results = append(*results, node)
	}
	for i := range node.Children {
		collectContainingText(&node.Children[i], substr, results)
	}
}

// Bounds returns the center coordinates from a bounds string "[x1,y1][x2,y2]".
func (n *UINode) Center() (int, int, error) {
	var x1, y1, x2, y2 int
	_, err := fmt.Sscanf(n.Bounds, "[%d,%d][%d,%d]", &x1, &y1, &x2, &y2)
	if err != nil {
		return 0, 0, fmt.Errorf("parse bounds %q: %w", n.Bounds, err)
	}
	return (x1 + x2) / 2, (y1 + y2) / 2, nil
}

// TapNode taps the center of the given UI node.
func (a *ADB) TapNode(n *UINode) error {
	cx, cy, err := n.Center()
	if err != nil {
		return err
	}
	return a.Tap(cx, cy)
}

// WaitForElement polls until an element with the given content-desc appears.
// Also matches content-desc that starts with the given string (for TextField elements
// where Qt appends placeholder text to the accessible name).
func (a *ADB) WaitForElement(contentDesc string, timeout time.Duration) (*UINode, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		hierarchy, err := a.DumpUI()
		if err != nil {
			time.Sleep(500 * time.Millisecond)
			continue
		}
		if node := hierarchy.FindByContentDesc(contentDesc); node != nil {
			return node, nil
		}
		// Also try prefix match for TextFields that concatenate name + placeholder
		if node := hierarchy.FindByContentDescPrefix(contentDesc + ","); node != nil {
			return node, nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil, fmt.Errorf("element %q not found within %s", contentDesc, timeout)
}

// WaitForText polls until an element containing the given text appears.
func (a *ADB) WaitForText(text string, timeout time.Duration) (*UINode, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		hierarchy, err := a.DumpUI()
		if err != nil {
			time.Sleep(500 * time.Millisecond)
			continue
		}
		if node := hierarchy.FindByText(text); node != nil {
			return node, nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil, fmt.Errorf("text %q not found within %s", text, timeout)
}

// ClearTextField selects all text in the focused field and deletes it.
func (a *ADB) ClearTextField() error {
	// CTRL+A to select all
	if _, err := a.Shell("input", "keyevent", "KEYCODE_MOVE_HOME"); err != nil {
		return err
	}
	if _, err := a.Shell("input", "keyevent", "--longpress", "KEYCODE_SHIFT_LEFT", "KEYCODE_MOVE_END"); err != nil {
		return err
	}
	_, err := a.Shell("input", "keyevent", "KEYCODE_DEL")
	return err
}

// WaitForTextContaining polls until a node containing the substring appears.
func (a *ADB) WaitForTextContaining(substr string, timeout time.Duration) ([]*UINode, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		hierarchy, err := a.DumpUI()
		if err != nil {
			time.Sleep(500 * time.Millisecond)
			continue
		}
		nodes := hierarchy.FindContainingText(substr)
		if len(nodes) > 0 {
			return nodes, nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil, fmt.Errorf("text containing %q not found within %s", substr, timeout)
}

// WaitForCondition polls until checkFn returns true.
func (a *ADB) WaitForCondition(desc string, timeout time.Duration, checkFn func() bool) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if checkFn() {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("condition %q not met within %s", desc, timeout)
}

// GetChildTexts recursively collects all non-empty Text attributes from children.
func (n *UINode) GetChildTexts() []string {
	var texts []string
	collectTexts(n, &texts)
	return texts
}

func collectTexts(node *UINode, texts *[]string) {
	if node.Text != "" {
		*texts = append(*texts, node.Text)
	}
	for i := range node.Children {
		collectTexts(&node.Children[i], texts)
	}
}

// GetLogcat returns recent logcat output filtered by tag.
func (a *ADB) GetLogcat(tag string, lines int) (string, error) {
	return a.Shell("logcat", "-t", fmt.Sprint(lines), "-s", tag+":V")
}

// Sleep pauses for the given duration.
func Sleep(d time.Duration) {
	time.Sleep(d)
}
