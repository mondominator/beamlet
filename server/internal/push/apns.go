package push

import (
	"fmt"
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

// APNsNotifier sends push notifications to a single iOS device via APNs.
type APNsNotifier struct {
	prodClient    *apns2.Client
	sandboxClient *apns2.Client
	bundleID      string
	userStore     *store.UserStore
}

func NewAPNsNotifier(keyPath, keyID, teamID, bundleID string, userStore *store.UserStore) (*APNsNotifier, error) {
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

	return &APNsNotifier{
		prodClient:    apns2.NewTokenClient(tok).Production(),
		sandboxClient: apns2.NewTokenClient(tok).Development(),
		bundleID:      bundleID,
		userStore:     userStore,
	}, nil
}

func (p *APNsNotifier) Send(device model.Device, pl Payload) error {
	notification := &apns2.Notification{
		DeviceToken: device.APNsToken,
		Topic:       p.bundleID,
		Payload: payload.NewPayload().
			AlertTitle(pl.AlertTitle).
			AlertBody(pl.AlertBody).
			MutableContent().
			Custom("file_id", pl.FileID).
			Sound("default").
			Badge(1),
	}
	log.Printf("push/apns: sending to device %s...", truncToken(device.APNsToken))

	// Try production first (TestFlight/App Store), fall back to sandbox (Xcode dev builds)
	res, err := p.prodClient.Push(notification)
	if err != nil {
		log.Printf("push/apns: prod network error for %s: %v, trying sandbox...", truncToken(device.APNsToken), err)
		res, err = p.sandboxClient.Push(notification)
	}
	if err != nil {
		return fmt.Errorf("both prod and sandbox failed: %w", err)
	}

	// If production rejects the token, try sandbox (device may be a dev/TestFlight build
	// with sandbox-registered token, or key may only work in sandbox)
	if res.StatusCode != 200 && (res.Reason == "BadDeviceToken" || res.Reason == "BadEnvironmentKeyInToken") {
		log.Printf("push/apns: prod returned %d/%s, trying sandbox for %s...", res.StatusCode, res.Reason, truncToken(device.APNsToken))
		res, err = p.sandboxClient.Push(notification)
		if err != nil {
			return fmt.Errorf("sandbox also failed: %w", err)
		}
	}

	log.Printf("push/apns: result for device %s: status=%d reason=%s", truncToken(device.APNsToken), res.StatusCode, res.Reason)
	if res.StatusCode == 410 || res.Reason == "Unregistered" {
		log.Printf("push/apns: deactivating device %s: %s", truncToken(device.APNsToken), res.Reason)
		p.userStore.DeactivateDevice(device.APNsToken)
	}

	return nil
}
