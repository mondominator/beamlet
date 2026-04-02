package cleanup

import (
	"log"
	"time"

	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
)

func RunOnce(fileStore *store.FileStore, diskStorage *storage.DiskStorage, inviteStore *store.InviteStore) (int, error) {
	expired, err := fileStore.ListExpired()
	if err != nil {
		return 0, err
	}

	deleted := 0
	for _, f := range expired {
		if f.FilePath != "" {
			diskStorage.Delete(f.FilePath)
		}
		if f.ThumbnailPath != "" {
			diskStorage.Delete(f.ThumbnailPath)
		}
		if err := fileStore.Delete(f.ID); err != nil {
			log.Printf("failed to delete expired file %s: %v", f.ID, err)
			continue
		}
		deleted++
	}

	// Clean up old invites (redeemed or expired more than 7 days ago)
	if inviteStore != nil {
		if invitesDeleted, err := inviteStore.DeleteExpired(); err != nil {
			log.Printf("invite cleanup error: %v", err)
		} else if invitesDeleted > 0 {
			log.Printf("cleaned up %d expired/redeemed invites", invitesDeleted)
		}
	}

	return deleted, nil
}

func StartScheduler(fileStore *store.FileStore, diskStorage *storage.DiskStorage, inviteStore *store.InviteStore, stop <-chan struct{}) {
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	if deleted, err := RunOnce(fileStore, diskStorage, inviteStore); err != nil {
		log.Printf("cleanup error: %v", err)
	} else if deleted > 0 {
		log.Printf("cleaned up %d expired files", deleted)
	}

	for {
		select {
		case <-ticker.C:
			if deleted, err := RunOnce(fileStore, diskStorage, inviteStore); err != nil {
				log.Printf("cleanup error: %v", err)
			} else if deleted > 0 {
				log.Printf("cleaned up %d expired files", deleted)
			}
		case <-stop:
			return
		}
	}
}
