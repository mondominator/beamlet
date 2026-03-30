package push

import "github.com/mondominator/beamlet/server/internal/model"

type APNsPusher struct{}

func (p *APNsPusher) Notify(recipientID, senderName string, file *model.File, excludeDeviceToken string) {
	// Stub - full implementation in Task 8
}
