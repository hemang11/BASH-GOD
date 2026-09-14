// god-archive writes a normalized gzip-compressed tar archive from one staged
// runtime directory. It is build tooling, not part of the installed runtime.
package main

import (
	"archive/tar"
	"compress/gzip"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var epoch = time.Unix(0, 0).UTC()

func main() {
	var source string
	var output string

	flag.StringVar(&source, "source", "", "staged directory to archive")
	flag.StringVar(&output, "output", "", "new .tar.gz file to create")
	flag.Parse()

	if flag.NArg() != 0 || source == "" || output == "" {
		fail("usage: god-archive --source DIRECTORY --output NEW_ARCHIVE.tar.gz")
	}
	if err := archive(source, output); err != nil {
		fail(err.Error())
	}
}

func archive(source, output string) error {
	absoluteSource, err := filepath.Abs(source)
	if err != nil {
		return fmt.Errorf("resolve source: %w", err)
	}
	info, err := os.Stat(absoluteSource)
	if err != nil {
		return fmt.Errorf("read source: %w", err)
	}
	if !info.IsDir() {
		return errors.New("source must be a directory")
	}

	absoluteOutput, err := filepath.Abs(output)
	if err != nil {
		return fmt.Errorf("resolve output: %w", err)
	}
	if _, err := os.Lstat(absoluteOutput); err == nil {
		return fmt.Errorf("refusing to overwrite archive: %s", absoluteOutput)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect output: %w", err)
	}

	relativePaths, err := listPaths(absoluteSource)
	if err != nil {
		return err
	}
	root := filepath.Base(filepath.Clean(absoluteSource))
	if root == "." || root == string(filepath.Separator) || root == "" {
		return errors.New("source must have a safe directory name")
	}

	temporary, err := os.CreateTemp(filepath.Dir(absoluteOutput), ".bash-god-archive.*")
	if err != nil {
		return fmt.Errorf("create archive: %w", err)
	}
	temporaryName := temporary.Name()
	removeTemporary := true
	defer func() {
		if removeTemporary {
			_ = os.Remove(temporaryName)
		}
	}()

	gzipWriter := gzip.NewWriter(temporary)
	gzipWriter.Name = ""
	gzipWriter.Comment = ""
	gzipWriter.ModTime = epoch
	gzipWriter.OS = 255
	tarWriter := tar.NewWriter(gzipWriter)

	for _, relativePath := range relativePaths {
		if err := writeEntry(tarWriter, absoluteSource, root, relativePath); err != nil {
			_ = tarWriter.Close()
			_ = gzipWriter.Close()
			_ = temporary.Close()
			return err
		}
	}
	if err := tarWriter.Close(); err != nil {
		_ = gzipWriter.Close()
		_ = temporary.Close()
		return fmt.Errorf("finish tar archive: %w", err)
	}
	if err := gzipWriter.Close(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("finish gzip archive: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close archive: %w", err)
	}
	if err := os.Rename(temporaryName, absoluteOutput); err != nil {
		return fmt.Errorf("publish archive: %w", err)
	}
	removeTemporary = false
	return nil
}

func listPaths(source string) ([]string, error) {
	paths := []string{"."}
	err := filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == source {
			return nil
		}
		relativePath, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		paths = append(paths, relativePath)
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("walk source: %w", err)
	}
	sort.Slice(paths, func(left, right int) bool {
		return filepath.ToSlash(paths[left]) < filepath.ToSlash(paths[right])
	})
	return paths, nil
}

func writeEntry(writer *tar.Writer, source, root, relativePath string) error {
	path := source
	if relativePath != "." {
		path = filepath.Join(source, relativePath)
	}
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("read staged entry %s: %w", relativePath, err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing symbolic link in staged runtime: %s", relativePath)
	}
	if !info.Mode().IsRegular() && !info.IsDir() {
		return fmt.Errorf("refusing non-regular staged entry: %s", relativePath)
	}

	name := root
	if relativePath != "." {
		name += "/" + filepath.ToSlash(relativePath)
	}
	header := &tar.Header{
		Name:     name,
		Mode:     int64(info.Mode().Perm()),
		ModTime:  epoch,
		Uid:      0,
		Gid:      0,
		Uname:    "",
		Gname:    "",
		Format:   tar.FormatUSTAR,
		Typeflag: tar.TypeReg,
		Size:     info.Size(),
	}
	if info.IsDir() {
		header.Name += "/"
		header.Typeflag = tar.TypeDir
		header.Size = 0
		if err := writer.WriteHeader(header); err != nil {
			return fmt.Errorf("write directory %s: %w", relativePath, err)
		}
		return nil
	}

	if err := writer.WriteHeader(header); err != nil {
		return fmt.Errorf("write file %s: %w", relativePath, err)
	}
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open staged file %s: %w", relativePath, err)
	}
	_, copyErr := io.Copy(writer, file)
	closeErr := file.Close()
	if copyErr != nil {
		return fmt.Errorf("archive staged file %s: %w", relativePath, copyErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close staged file %s: %w", relativePath, closeErr)
	}
	return nil
}

func fail(message string) {
	fmt.Fprintf(os.Stderr, "god-archive: %s\n", strings.TrimSpace(message))
	os.Exit(1)
}
