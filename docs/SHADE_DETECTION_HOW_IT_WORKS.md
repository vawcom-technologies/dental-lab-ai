# Shade Detection

## Patient selection

A patient must be selected before shade detection can run.

## Capture with camera

The user may use the camera to capture an image on the spot. Refer to the in-app guides for framing and orientation of the image. After capturing, use Open with Shade Detection to forward the image to the Shade Detection page. The image is attached to the patient record and analysis begins automatically.

## Upload an existing image

Alternatively, use the upload image button on the Shade Detection page to attach preexisting images. If an upload cannot be read, export the photo as JPEG and try again.

## Image requirements

Ensure that the image is clear, that only the teeth and mouth area are visible, and that the image is well lit.

## Detection

The AI algorithm is applied to the image. Up to 16 teeth are detected. Each tooth is segmented into 3 parts: cervical, middle, and incisal.

For each segment, the algorithm provides the closest tooth shade on the VITA Classical scale, with a match percentage. Similar shades are shown for the focused segment. Best overall shades across all detected teeth are also shown.

## Gum shade

Gum color is also detected and matched to gingiva shades G1 through G5.

## Corrections

The user may add or delete a tooth and refine edges in case of exceptions. Adjust edges allows the outline to be corrected. After Apply, zone shades for that tooth are recalculated from the updated outline.

A tooth may also be selected from the Tooth Selection chart using FDI numbering.

## Manual override

The dentist may override the closest match shade if necessary. Manual Override supports all VITA Classical shades, Target shades M1 through M3, and gum shades G1 through G5. Target shades are available for manual selection only and are not produced by automatic matching.

Overrides may be applied per tooth segment and for gum shade. Detected and overridden values are both retained. The effective shade is the override when one exists, otherwise the detected shade.

## Accept or save

The dentist may Accept AI to keep the detected shade, or Save override to store a manual selection.

## Sessions and storage

Results are stored with the patient record. The Session panel lists saved shade results from that session. Entries may be reopened for editing. Shade data stays with the patient record after the session.
