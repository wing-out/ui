// Package e2e contains end-to-end tests for wingout2.
//
// Tests are split into two categories:
// - Headless E2E: Uses the real Go backend with mock backends, Qt frontend in offscreen mode.
// - Full E2E: Uses real Go backend with real FFStream/StreamD, Qt frontend.
//
// Build tag: test_e2e
package e2e
