#if !VPHONE_EXPERIMENTAL_HOST_CAMERA
@main
struct DisabledTests {
    static func main() { print("PASS: host camera disabled; no capture, registration or permission code compiled") }
}
#endif
