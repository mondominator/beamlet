package storage

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

func GenerateThumbnail(srcPath, destDir, mimeType string) (string, error) {
	if !strings.HasPrefix(mimeType, "image/") && !strings.HasPrefix(mimeType, "video/") {
		return "", nil
	}

	thumbDir := filepath.Join(destDir, "thumbs")
	os.MkdirAll(thumbDir, 0755)
	thumbName := uuid.New().String() + ".jpg"
	thumbPath := filepath.Join(thumbDir, thumbName)

	if strings.HasPrefix(mimeType, "image/") {
		cmd := exec.Command("convert", srcPath, "-auto-orient", "-thumbnail", "200x200>", "-quality", "80", thumbPath)
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("generate image thumbnail: %w", err)
		}
	} else if strings.HasPrefix(mimeType, "video/") {
		cmd := exec.Command("ffmpeg", "-i", srcPath, "-vframes", "1", "-vf", "scale=200:-1", "-y", thumbPath)
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("generate video thumbnail: %w", err)
		}
	}

	return thumbPath, nil
}
