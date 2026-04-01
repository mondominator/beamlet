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
	client    *apns2.Client
	bundleID  string
	userStore *store.UserStore
}

func NewAPNsPusher(keyPath, keyID, teamID, bundleID string, sandbox bool, userStore *store.UserStore) (*APNsPusher, error) {
	authKey, err := token.AuthKeyFromFile(keyPath)
	if err != nil {
		return nil, err
	}

	tok := &token.Token{
		AuthKey: authKey,
		KeyID:   keyID,
		TeamID:  teamID,
	}

	var client *apns2.Client
	if sandbox {
		client = apns2.NewTokenClient(tok).Development()
		log.Println("APNs configured in SANDBOX (development) mode")
	} else {
		client = apns2.NewTokenClient(tok).Production()
		log.Println("APNs configured in PRODUCTION mode")
	}

	return &APNsPusher{
		client:    client,
		bundleID:  bundleID,
		userStore: userStore,
	}, nil
}

func (p *APNsPusher) Notify(recipientID, senderName string, file *model.File, excludeDeviceToken string) {
	devices, err := p.userStore.GetActiveDevices(recipientID)
	if err != nil {
		log.Printf("failed to get devices for %s: %v", recipientID, err)
		return
	}

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
			continue
		}
		notification.DeviceToken = device.APNsToken
		res, err := p.client.Push(notification)
		if err != nil {
			log.Printf("push failed for device %s: %v", device.APNsToken, err)
			continue
		}
		if res.StatusCode == 410 || res.Reason == "Unregistered" {
			log.Printf("deactivating device %s: %s", device.APNsToken, res.Reason)
			p.userStore.DeactivateDevice(device.APNsToken)
		}
	}
}
