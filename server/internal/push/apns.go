package push

import (
	"log"
	"strings"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
)

func truncToken(t string) string {
	if len(t) > 16 {
		return t[:16]
	}
	return t
}

type Payload struct {
	AlertTitle string
	AlertBody  string
	FileID     string
}

func BuildPayload(senderName, fileType, fileID string) Payload {
	var body string
	switch {
	case strings.HasPrefix(fileType, "image/"):
		body = "sent you a photo"
	case strings.HasPrefix(fileType, "video/"):
		body = "sent you a video"
	case strings.HasPrefix(fileType, "text/"):
		body = "sent you a message"
	default:
		body = "sent you a file"
	}

	return Payload{
		AlertTitle: senderName,
		AlertBody:  body,
		FileID:     fileID,
	}
}

type APNsPusher struct {
	prodClient    *apns2.Client
	sandboxClient *apns2.Client
	bundleID      string
	userStore     *store.UserStore
}

func NewAPNsPusher(keyPath, keyID, teamID, bundleID string, userStore *store.UserStore) (*APNsPusher, error) {
	authKey, err := token.AuthKeyFromFile(keyPath)
	if err != nil {
		return nil, err
	}

	tok := &token.Token{
		AuthKey: authKey,
		KeyID:   keyID,
		TeamID:  teamID,
	}

	log.Println("APNs configured (sends to both production and sandbox)")

	return &APNsPusher{
		prodClient:    apns2.NewTokenClient(tok).Production(),
		sandboxClient: apns2.NewTokenClient(tok).Development(),
		bundleID:      bundleID,
		userStore:     userStore,
	}, nil
}

func (p *APNsPusher) Notify(recipientID, senderName string, file *model.File, excludeDeviceToken string) {
	log.Printf("push: notifying recipient %s from %s", recipientID, senderName)

	devices, err := p.userStore.GetActiveDevices(recipientID)
	if err != nil {
		log.Printf("push: failed to get devices for %s: %v", recipientID, err)
		return
	}

	log.Printf("push: found %d active devices for %s", len(devices), recipientID)

	pl := BuildPayload(senderName, file.FileType, file.ID)

	notification := &apns2.Notification{
		Topic: p.bundleID,
		Payload: payload.NewPayload().
			AlertTitle(pl.AlertTitle).
			AlertBody(pl.AlertBody).
			MutableContent().
			Custom("file_id", pl.FileID).
			Sound("default").
			Badge(1),
	}

	for _, device := range devices {
		if device.APNsToken == excludeDeviceToken {
			log.Printf("push: skipping sender device %s...", truncToken(device.APNsToken))
			continue
		}
		notification.DeviceToken = device.APNsToken
		log.Printf("push: sending to device %s...", truncToken(device.APNsToken))

		// Try production first (TestFlight/App Store), fall back to sandbox (Xcode dev builds)
		res, err := p.prodClient.Push(notification)
		if err != nil {
			log.Printf("push: prod network error for %s: %v, trying sandbox...", truncToken(device.APNsToken), err)
			res, err = p.sandboxClient.Push(notification)
		}
		if err != nil {
			log.Printf("push: both failed for device %s: %v", truncToken(device.APNsToken), err)
			continue
		}

		// If production rejects the token, try sandbox (device may be a dev/TestFlight build
		// with sandbox-registered token, or key may only work in sandbox)
		if res.StatusCode != 200 && (res.Reason == "BadDeviceToken" || res.Reason == "BadEnvironmentKeyInToken") {
			log.Printf("push: prod returned %d/%s, trying sandbox for %s...", res.StatusCode, res.Reason, truncToken(device.APNsToken))
			res, err = p.sandboxClient.Push(notification)
			if err != nil {
				log.Printf("push: sandbox also failed for %s: %v", truncToken(device.APNsToken), err)
				continue
			}
		}

		log.Printf("push: result for device %s: status=%d reason=%s", truncToken(device.APNsToken), res.StatusCode, res.Reason)
		if res.StatusCode == 410 || res.Reason == "Unregistered" {
			log.Printf("push: deactivating device %s: %s", truncToken(device.APNsToken), res.Reason)
			p.userStore.DeactivateDevice(device.APNsToken)
		}
	}
}
