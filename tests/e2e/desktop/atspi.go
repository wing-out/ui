//go:build desktop_e2e

// Package desktop provides a Go-based AT-SPI2 test harness for driving
// the WingOut Qt desktop app and verifying its behavior via accessibility.
package desktop

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// ATSPIClient interacts with desktop UI via AT-SPI2 accessibility.
// It uses python3 with pyatspi2 (gi.repository.Atspi) and xdotool
// to communicate with the accessibility tree and simulate input.
type ATSPIClient struct {
	appPID  int
	appName string
}

// UINode represents a node in the accessibility tree.
type UINode struct {
	Name        string    `json:"name"`
	Role        string    `json:"role"`
	Description string    `json:"description"`
	Value       string    `json:"value"`
	Children    []*UINode `json:"children"`
	BusName     string    `json:"-"`
	ObjPath     string    `json:"-"`
}

// NewATSPIClient creates a new AT-SPI2 client.
func NewATSPIClient(appName string) *ATSPIClient {
	return &ATSPIClient{appName: appName}
}

// SetPID sets the application PID for focused searches.
func (c *ATSPIClient) SetPID(pid int) {
	c.appPID = pid
}

// DumpTree uses python3 with pyatspi2 to dump the accessibility tree
// for the application matching appName or appPID.
func (c *ATSPIClient) DumpTree() (*UINode, error) {
	script := fmt.Sprintf(`
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi
import json, sys

def dump_node(node, depth=0):
    try:
        name = node.get_name() or ""
        role = node.get_role_name() or ""
        desc = node.get_description() or ""
        result = {"name": name, "role": role, "description": desc, "children": []}
        if depth < 10:
            for i in range(node.get_child_count()):
                child = node.get_child_at_index(i)
                if child:
                    result["children"].append(dump_node(child, depth+1))
        return result
    except Exception:
        return {"name": "", "role": "", "description": "", "children": []}

desktop = Atspi.get_desktop(0)
for i in range(desktop.get_child_count()):
    app = desktop.get_child_at_index(i)
    if app and ("%s" in (app.get_name() or "").lower() or app.get_process_id() == %d):
        tree = dump_node(app)
        print(json.dumps(tree))
        sys.exit(0)
print("{}")
`, c.appName, c.appPID)

	cmd := exec.Command("python3", "-c", script)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("atspi dump failed: %w", err)
	}
	return parseUITree(out)
}

// parseUITree parses JSON from the python script into a UINode tree.
func parseUITree(data []byte) (*UINode, error) {
	var node UINode
	if err := json.Unmarshal(data, &node); err != nil {
		return nil, fmt.Errorf("parse tree: %w", err)
	}
	return &node, nil
}

// FindByName searches the tree for a node with matching name (exact).
func (n *UINode) FindByName(name string) *UINode {
	if n == nil {
		return nil
	}
	if n.Name == name {
		return n
	}
	for _, child := range n.Children {
		if found := child.FindByName(name); found != nil {
			return found
		}
	}
	return nil
}

// FindByDescription searches the tree for a node with matching accessible description.
func (n *UINode) FindByDescription(desc string) *UINode {
	if n == nil {
		return nil
	}
	if n.Description == desc {
		return n
	}
	for _, child := range n.Children {
		if found := child.FindByDescription(desc); found != nil {
			return found
		}
	}
	return nil
}

// FindContainingText searches for nodes whose name contains text (case-insensitive).
func (n *UINode) FindContainingText(text string) []*UINode {
	if n == nil {
		return nil
	}
	var results []*UINode
	lower := strings.ToLower(text)
	if strings.Contains(strings.ToLower(n.Name), lower) ||
		strings.Contains(strings.ToLower(n.Description), lower) {
		results = append(results, n)
	}
	for _, child := range n.Children {
		results = append(results, child.FindContainingText(text)...)
	}
	return results
}

// FindByRole searches for nodes with a specific AT-SPI role.
func (n *UINode) FindByRole(role string) []*UINode {
	if n == nil {
		return nil
	}
	var results []*UINode
	if strings.EqualFold(n.Role, role) {
		results = append(results, n)
	}
	for _, child := range n.Children {
		results = append(results, child.FindByRole(role)...)
	}
	return results
}

// GetAllTexts returns all text content (names) in the subtree.
func (n *UINode) GetAllTexts() []string {
	if n == nil {
		return nil
	}
	var texts []string
	if n.Name != "" {
		texts = append(texts, n.Name)
	}
	if n.Description != "" {
		texts = append(texts, n.Description)
	}
	for _, child := range n.Children {
		texts = append(texts, child.GetAllTexts()...)
	}
	return texts
}

// GetChildTexts recursively collects all non-empty Name and Description values from children.
func (n *UINode) GetChildTexts() []string {
	if n == nil {
		return nil
	}
	var texts []string
	for _, child := range n.Children {
		if child.Name != "" {
			texts = append(texts, child.Name)
		}
		if child.Description != "" {
			texts = append(texts, child.Description)
		}
		texts = append(texts, child.GetChildTexts()...)
	}
	return texts
}

// ActivateByName uses AT-SPI2 to activate/click a node by name or description.
func (c *ATSPIClient) ActivateByName(name string) error {
	script := fmt.Sprintf(`
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi
import sys

def find_and_activate(node, target, depth=0):
    try:
        if node.get_name() == target or node.get_description() == target:
            actions = node.get_action_iface()
            if actions and actions.get_n_actions() > 0:
                actions.do_action(0)
                return True
            comp = node.get_component_iface()
            if comp:
                pos = comp.get_position(Atspi.CoordType.SCREEN)
                size = comp.get_size()
                if pos and size:
                    import subprocess
                    x = pos.x + size.x // 2
                    y = pos.y + size.y // 2
                    subprocess.run(["xdotool", "mousemove", str(x), str(y), "click", "1"])
                    return True
        if depth < 10:
            for i in range(node.get_child_count()):
                child = node.get_child_at_index(i)
                if child and find_and_activate(child, target, depth+1):
                    return True
    except Exception:
        pass
    return False

desktop = Atspi.get_desktop(0)
for i in range(desktop.get_child_count()):
    app = desktop.get_child_at_index(i)
    if app and ("%s" in (app.get_name() or "").lower() or app.get_process_id() == %d):
        if find_and_activate(app, "%s"):
            sys.exit(0)
sys.exit(1)
`, c.appName, c.appPID, name)

	cmd := exec.Command("python3", "-c", script)
	return cmd.Run()
}

// TypeText uses xdotool to type text into the focused element.
func (c *ATSPIClient) TypeText(text string) error {
	cmd := exec.Command("xdotool", "type", "--clearmodifiers", text)
	return cmd.Run()
}

// PressKey uses xdotool to press a specific key.
func (c *ATSPIClient) PressKey(key string) error {
	cmd := exec.Command("xdotool", "key", key)
	return cmd.Run()
}

// WaitForElement polls until an element with the given name or description appears.
func (c *ATSPIClient) WaitForElement(name string, timeout time.Duration) (*UINode, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		tree, err := c.DumpTree()
		if err == nil && tree != nil {
			if node := tree.FindByName(name); node != nil {
				return node, nil
			}
			if node := tree.FindByDescription(name); node != nil {
				return node, nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil, fmt.Errorf("element %q not found within %v", name, timeout)
}

// WaitForText polls until text content appears somewhere in the tree.
func (c *ATSPIClient) WaitForText(text string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		tree, err := c.DumpTree()
		if err == nil && tree != nil {
			if len(tree.FindContainingText(text)) > 0 {
				return nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("text %q not found within %v", text, timeout)
}

// WaitForCondition polls until checkFn returns true.
func (c *ATSPIClient) WaitForCondition(desc string, timeout time.Duration, checkFn func() bool) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if checkFn() {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("condition %q not met within %v", desc, timeout)
}

// Screenshot captures a screenshot using scrot or import (ImageMagick).
func (c *ATSPIClient) Screenshot(path string) error {
	cmd := exec.Command("scrot", path)
	if err := cmd.Run(); err != nil {
		// Fallback to import (ImageMagick)
		cmd = exec.Command("import", "-window", "root", path)
		return cmd.Run()
	}
	return nil
}

// Sleep pauses for the given duration.
func Sleep(d time.Duration) {
	time.Sleep(d)
}
