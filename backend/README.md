# Backend

Prefered backends we want to use is BoofCV, which is very performant and pretty good when it comes to scanning real-life QR codes. Unfortunatelly even in the age of AGI armv7a-linux-androideabi is not commonly supported, and for the sake of supporting all platforms with all of their perks we have a ~~nice~~ C ABI defined to scan QR codes


## ABI

```
// Returns 0 on success UB on failure.
int SCANQRC_<plugin>_init(void);

/*
 * Detect QR codes in an 8-bit grayscale buffer (row-major, stride bytes per row).
 * Returns a malloc'd JSON envelope string, or NULL if malloc failed.
 * Caller must SCANQRC_<plugin>_qr_free() the pointer.
 */
char* SCANQRC_<plugin>_qr_detect(const uint8_t *gray, int width, int height, int stride);
void SCANQRC_<plugin>_qr_free(char *json);
void SCANQRC_<plugin>_shutdown(void);
```

That means that we can support infinite amount of QR code scanners on all platforms

```
SCANQRC_<plugin>_<function>
```

is the schema that we use and all functions are the one described above.

Known plugins:

- `simple` → `SCANQRC_simple_*`
- `boofcvc` → `SCANQRC_boofcvc_*`

This would be about the extend of what is supported.

## Implementations


### `simple`

Embedded `simple` implementation - visible in `./simple` is the bare minimum. Note that we do not package it by default in `fast_scanner` - that task is left as an excercise to the user and servers more as an example rather than the go-to implementation. Fast scanner is **not** fast with only the default implementation.

### `boofcvc` / [scanqr_c](https://github.com/MrCyjaneK/scanqr_c)

Compiled version of `BoofCV` with C interface. It is pretty fast. And pretty good.

## How it's used

Native platforms send 8-bit grayscale frames to Dart. Dart probes known plugins (`simple`, `boofcvc`) with `DynamicLibrary.open` and skips missing ones. Whenever a frame comes into processing it does the following:

0. Checks if implementation is busy processing anything else from the past - skip this implementation if true.
1. Check if implementation was started before - if not `_init`.
2. Copy the grayscale into native memory for the FFI call
3. Flip the boolean to true and send the frame to that implementation's isolate (there's another skip if a new frame arrives while that isolate is still working)
4. Get JSON back from the isolate, call `_free`
5. Return the QR scan to the user.

so there's always only one `_qr_detect` running at a given time per implementation.

If conversion or detect is busy, **processing** frames are skipped. The camera preview is independent and must keep updating.
