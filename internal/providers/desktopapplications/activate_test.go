package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveDesktopExecNixStoreBin(t *testing.T) {
	oldStoreDir := nixStoreDir
	t.Cleanup(func() { nixStoreDir = oldStoreDir })

	nixStoreDir = filepath.Join(t.TempDir(), "nix", "store")
	pkgDir := filepath.Join(nixStoreDir, "abc123-test-app-1.0")
	binPath := filepath.Join(pkgDir, "bin", "test-app")
	if err := os.MkdirAll(filepath.Dir(binPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(binPath, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	f := &DesktopFile{RealPath: filepath.Join(pkgDir, "share", "applications", "test-app.desktop")}
	got := resolveDesktopExec(f, "test-app --name test-app %U")
	want := binPath + " --name test-app %U"
	if got != want {
		t.Fatalf("resolveDesktopExec() = %q, want %q", got, want)
	}
}

func TestResolveDesktopExecLeavesMissingBinUnchanged(t *testing.T) {
	oldStoreDir := nixStoreDir
	t.Cleanup(func() { nixStoreDir = oldStoreDir })

	nixStoreDir = filepath.Join(t.TempDir(), "nix", "store")
	pkgDir := filepath.Join(nixStoreDir, "abc123-test-app-1.0")
	f := &DesktopFile{RealPath: filepath.Join(pkgDir, "share", "applications", "test-app.desktop")}

	command := "test-app --name test-app %U"
	if got := resolveDesktopExec(f, command); got != command {
		t.Fatalf("resolveDesktopExec() = %q, want unchanged %q", got, command)
	}
}

func TestResolveDesktopExecLeavesNonNixStoreUnchanged(t *testing.T) {
	command := "test-app --name test-app %U"
	f := &DesktopFile{RealPath: "/usr/share/applications/test-app.desktop"}
	if got := resolveDesktopExec(f, command); got != command {
		t.Fatalf("resolveDesktopExec() = %q, want unchanged %q", got, command)
	}
}
