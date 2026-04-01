package api

import (
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
)

func (s *Server) InviteWebPage(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	if token == "" {
		http.Error(w, "invalid invite", http.StatusBadRequest)
		return
	}

	// Verify the invite is valid
	invite, err := s.InviteStore.FindByToken(token)
	if err != nil || invite == nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, expiredPage)
		return
	}

	// Get creator name
	creatorName := "someone"
	if creator, err := s.UserStore.GetByID(invite.CreatorID); err == nil {
		creatorName = creator.Name
	}

	// Build the QR payload URL for the app
	serverURL := fmt.Sprintf("%s://%s", scheme(r), r.Host)
	qrPayload := fmt.Sprintf(`{"url":"%s","invite":"%s"}`, serverURL, token)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, invitePage, creatorName, creatorName, qrPayload, serverURL, token)
}

func scheme(r *http.Request) string {
	if r.TLS != nil {
		return "https"
	}
	if proto := r.Header.Get("X-Forwarded-Proto"); proto != "" {
		return proto
	}
	return "http"
}

var expiredPage = `<!DOCTYPE html>
<html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beamlet - Invite Expired</title>
<style>
body{margin:0;background:#08090d;color:#e8ecf4;font-family:-apple-system,system-ui,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;text-align:center}
.c{max-width:400px;padding:40px}
h1{font-size:2rem;margin-bottom:8px}
p{color:#6b7a8d;line-height:1.6}
</style>
</head><body>
<div class="c">
<div style="font-size:60px;margin-bottom:20px">⏰</div>
<h1>Invite Expired</h1>
<p>This invite link is no longer valid. Ask the person who shared it to send you a new one.</p>
</div>
</body></html>`

var invitePage = `<!DOCTYPE html>
<html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beamlet - %s invited you</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#08090d;color:#e8ecf4;font-family:-apple-system,system-ui,sans-serif;min-height:100vh;display:flex;justify-content:center;align-items:center}
.card{max-width:420px;padding:48px 32px;text-align:center}
.icon{width:80px;height:80px;margin:0 auto 24px;border-radius:18px;background:linear-gradient(135deg,#0a0f1e,#141e33);display:flex;align-items:center;justify-content:center}
.icon svg{width:48px;height:48px}
h1{font-size:1.8rem;font-weight:700;margin-bottom:8px;letter-spacing:-0.02em}
.sub{color:#6b7a8d;margin-bottom:32px;line-height:1.5}
.name{color:#8b5cf6;font-weight:600}
.btn{display:block;width:100%%;padding:16px;border:none;border-radius:12px;font-size:1.1rem;font-weight:600;cursor:pointer;text-decoration:none;margin-bottom:12px;transition:transform 0.2s}
.btn:hover{transform:scale(1.02)}
.btn-primary{background:linear-gradient(135deg,#8b5cf6,#3b82f6);color:white}
.btn-secondary{background:rgba(255,255,255,0.08);color:#e8ecf4;border:1px solid rgba(255,255,255,0.1)}
.divider{display:flex;align-items:center;gap:12px;margin:24px 0;color:#3a4558;font-size:0.85rem}
.divider::before,.divider::after{content:'';flex:1;height:1px;background:#1a2332}
.manual{color:#4a5568;font-size:0.85rem;line-height:1.6;margin-top:16px}
.token{background:#0f1520;border:1px solid #1a2332;border-radius:8px;padding:10px;font-family:monospace;font-size:0.8rem;color:#06b6d4;word-break:break-all;margin-top:8px;user-select:all}
</style>
</head><body>
<div class="card">
<div class="icon">
<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0%%" y1="0%%" x2="100%%" y2="100%%"><stop offset="0%%" stop-color="#8b5cf6"/><stop offset="100%%" stop-color="#3b82f6"/></linearGradient></defs>
<polygon points="50,105 150,55 110,145" fill="url(#g)"/>
<polygon points="50,105 150,55 100,110" fill="white" opacity="0.15"/>
</svg>
</div>
<h1>You're invited!</h1>
<p class="sub"><span class="name">%s</span> wants to connect with you on Beamlet</p>
<a class="btn btn-primary" href="beamlet://invite?payload=%s">Open in Beamlet</a>
<a class="btn btn-secondary" href="https://apps.apple.com/app/beamlet">Get Beamlet</a>
<div class="divider">or setup manually</div>
<p class="manual">Server URL</p>
<div class="token">%s</div>
<p class="manual" style="margin-top:12px">Invite Token</p>
<div class="token">%s</div>
</div>
</body></html>`
