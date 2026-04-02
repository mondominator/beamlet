package push

import (
	"log"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
)

// Notifier sends a push notification to a single device.
type Notifier interface {
	Send(device model.Device, pl Payload) error
}

// Pusher iterates a recipient's devices and dispatches to the correct
// platform-specific Notifier (APNs for iOS, FCM for Android).
type Pusher struct {
	apns      Notifier
	fcm       Notifier
	userStore *store.UserStore
}

func NewPusher(apns Notifier, fcm Notifier, userStore *store.UserStore) *Pusher {
	return &Pusher{apns: apns, fcm: fcm, userStore: userStore}
}

func (p *Pusher) Notify(recipientID, senderName string, file *model.File, excludeDeviceToken string) {
	log.Printf("push: notifying recipient %s from %s", recipientID, senderName)

	devices, err := p.userStore.GetActiveDevices(recipientID)
	if err != nil {
		log.Printf("push: failed to get devices for %s: %v", recipientID, err)
		return
	}

	log.Printf("push: found %d active devices for %s", len(devices), recipientID)

	pl := BuildPayload(senderName, file.FileType, file.ID)

	for _, device := range devices {
		if device.APNsToken == excludeDeviceToken {
			log.Printf("push: skipping sender device %s...", truncToken(device.APNsToken))
			continue
		}

		var notifier Notifier
		switch device.Platform {
		case "android":
			notifier = p.fcm
		default:
			notifier = p.apns
		}

		if notifier == nil {
			log.Printf("push: no notifier for platform %q, skipping device %s...", device.Platform, truncToken(device.APNsToken))
			continue
		}

		if err := notifier.Send(device, pl); err != nil {
			log.Printf("push: failed for device %s (platform=%s): %v", truncToken(device.APNsToken), device.Platform, err)
		}
	}
}
