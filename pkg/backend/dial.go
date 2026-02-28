package backend

import (
	"crypto/tls"
	"net"
	"time"

	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
)

// dialCredentials probes addr with a short TLS handshake to determine whether
// the server speaks TLS. Returns TLS credentials (with verification skipped)
// if TLS is detected, otherwise returns insecure (plaintext) credentials.
func dialCredentials(addr string) credentials.TransportCredentials {
	conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		// Can't reach the server; default to TLS and let gRPC report the error later.
		return credentials.NewTLS(&tls.Config{InsecureSkipVerify: true})
	}
	defer conn.Close()

	tlsConn := tls.Client(conn, &tls.Config{InsecureSkipVerify: true, ServerName: addr})
	tlsConn.SetDeadline(time.Now().Add(2 * time.Second))
	if err := tlsConn.Handshake(); err != nil {
		return insecure.NewCredentials()
	}
	return credentials.NewTLS(&tls.Config{InsecureSkipVerify: true})
}
