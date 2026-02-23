// Package qr generates QR codes for bootstrapping openme client configurations.
//
// The QR payload is a JSON object containing the minimum fields needed to
// configure a mobile or new desktop client. Since the payload includes the
// client's private key, callers should warn users to treat the QR as a secret.
package qr

import (
	"encoding/json"
	"fmt"
	"os"

	goqr "github.com/skip2/go-qrcode"
)

// Payload is the data encoded into the QR code.
type Payload struct {
	// ProfileName is the suggested name for this profile on the client.
	ProfileName string `json:"profile"`

	// ServerHost is the server hostname or IP.
	ServerHost string `json:"host"`

	// ServerUDPPort is the UDP knock port.
	ServerUDPPort uint16 `json:"udp_port"`

	// ServerPubKey is the base64-encoded Curve25519 public key of the server.
	ServerPubKey string `json:"server_pubkey"`

	// ClientPrivKey is the base64-encoded Ed25519 private key of the client.
	// Omitted if GenerateOptions.OmitPrivateKey is true.
	ClientPrivKey string `json:"client_privkey,omitempty"`

	// ClientPubKey is the base64-encoded Ed25519 public key of the client.
	ClientPubKey string `json:"client_pubkey"`
}

// GenerateOptions controls QR code generation.
type GenerateOptions struct {
	// OmitPrivateKey omits the client private key from the QR payload.
	// Use this when the mobile app will generate its own keypair.
	OmitPrivateKey bool

	// Size is the QR image size in pixels (default: 256).
	Size int

	// OutputPath is the file path to write the QR PNG to.
	// If empty, the QR is printed to the terminal as ASCII art.
	OutputPath string

	// RecoveryLevel is the QR error correction level (L, M, Q, H).
	// Default is M.
	RecoveryLevel goqr.RecoveryLevel
}

// Generate encodes payload into a QR code. If opts.OutputPath is set, the PNG
// is written to that path; otherwise ASCII art is printed to stdout.
func Generate(payload *Payload, opts *GenerateOptions) error {
	if opts == nil {
		opts = &GenerateOptions{}
	}
	if opts.Size == 0 {
		opts.Size = 256
	}
	if opts.RecoveryLevel == 0 {
		opts.RecoveryLevel = goqr.Medium
	}

	p := *payload
	if opts.OmitPrivateKey {
		p.ClientPrivKey = ""
	}

	data, err := json.Marshal(&p)
	if err != nil {
		return fmt.Errorf("marshalling QR payload: %w", err)
	}

	if opts.OutputPath != "" {
		if err := goqr.WriteFile(string(data), opts.RecoveryLevel, opts.Size, opts.OutputPath); err != nil {
			return fmt.Errorf("writing QR PNG to %s: %w", opts.OutputPath, err)
		}
		fmt.Fprintf(os.Stdout, "QR code written to %s\n", opts.OutputPath)
		return nil
	}

	// Print ASCII art to terminal.
	q, err := goqr.New(string(data), opts.RecoveryLevel)
	if err != nil {
		return fmt.Errorf("generating QR: %w", err)
	}
	fmt.Println(q.ToSmallString(false))
	return nil
}
