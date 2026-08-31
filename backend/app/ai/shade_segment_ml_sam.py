"""Light HQ-SAM helpers for SegmentAnyTooth (adapted from upstream MIT code)."""

from __future__ import annotations

from typing import Any

import numpy as np


def sam_load(ckpt_path: str) -> Any:
    import torch
    from segment_anything_hq import sam_model_registry

    sam = sam_model_registry["vit_tiny"](checkpoint=ckpt_path)
    sam.eval()
    if torch.cuda.is_available():
        sam.to(device="cuda")
    return sam


def sam_predict(
    sam: Any,
    boxes_xyxy: np.ndarray,
    image: np.ndarray,
    batch_size: int = 10,
) -> np.ndarray:
    import torch

    from app.ai.shade_segment_ml_sam import SamMobilePredictor

    device = sam.device
    predictor = SamMobilePredictor(sam)
    predictor.set_image(image)

    if len(boxes_xyxy) == 0:
        return np.zeros((0, *image.shape[:2]), dtype=np.uint8)

    batch_boxes = np.split(
        boxes_xyxy, range(batch_size, len(boxes_xyxy), batch_size)
    )
    batch_masks: list[np.ndarray] = []

    with torch.no_grad():
        for boxes in batch_boxes:
            transformed_boxes = predictor.transform.apply_boxes_torch(
                torch.tensor(boxes), image.shape[:2]
            ).to(device)

            sam_masks, _, _ = predictor.predict_torch(
                point_coords=None,
                point_labels=None,
                boxes=transformed_boxes,
                multimask_output=False,
                hq_token_only=False,
            )

            sam_masks_np = sam_masks.squeeze().cpu().numpy().astype(np.uint8)

            if len(sam_masks_np.shape) == 2:
                batch_masks.append(sam_masks_np)
            else:
                batch_masks.extend(sam_masks_np.tolist())

    return np.stack(batch_masks)


# ---------------------------------------------------------------------------
# SamMobilePredictor — from SegmentAnyTooth / Meta SAM (MIT)
# ---------------------------------------------------------------------------


class SamMobilePredictor:
    def __init__(self, sam_model: Any) -> None:
        import torch
        from segment_anything_hq.modeling import Sam
        from segment_anything_hq.utils.transforms import ResizeLongestSide

        self.model: Sam = sam_model
        self.transform = ResizeLongestSide(sam_model.image_encoder.img_size)
        self.reset_image()

    def set_image(self, image: np.ndarray, image_format: str = "RGB") -> None:
        import torch

        assert image_format in ["RGB", "BGR"]
        if image_format != self.model.image_format:
            image = image[..., ::-1]

        input_image = self.transform.apply_image(image)
        input_image_torch = torch.as_tensor(input_image, device=self.device)
        input_image_torch = input_image_torch.permute(2, 0, 1).contiguous()[
            None, :, :, :
        ]
        input_image_torch = input_image_torch.float() / 255.0
        self.set_torch_image(input_image_torch, image.shape[:2])

    def set_torch_image(
        self, transformed_image: Any, original_image_size: tuple[int, ...]
    ) -> None:
        import torch
        from torch.nn import functional as F

        self.reset_image()
        self.original_size = original_image_size
        self.input_size = tuple(transformed_image.shape[-2:])
        input_image = self.preprocess(transformed_image)
        self.features, self.interm_features = self.model.image_encoder(input_image)
        self.is_image_set = True

    def preprocess(self, x: Any) -> Any:
        from torch.nn import functional as F

        h, w = x.shape[-2:]
        padh = self.model.image_encoder.img_size - h
        padw = self.model.image_encoder.img_size - w
        return F.pad(x, (0, padw, 0, padh))

    def predict_torch(
        self,
        point_coords: Any | None,
        point_labels: Any | None,
        boxes: Any | None = None,
        mask_input: Any | None = None,
        multimask_output: bool = True,
        return_logits: bool = False,
        hq_token_only: bool = False,
    ) -> tuple[Any, Any, Any]:
        if not self.is_image_set:
            raise RuntimeError("An image must be set with .set_image(...) first.")

        points = (point_coords, point_labels) if point_coords is not None else None

        sparse_embeddings, dense_embeddings = self.model.prompt_encoder(
            points=points,
            boxes=boxes,
            masks=mask_input,
        )

        low_res_masks, iou_predictions = self.model.mask_decoder(
            image_embeddings=self.features,
            image_pe=self.model.prompt_encoder.get_dense_pe(),
            sparse_prompt_embeddings=sparse_embeddings,
            dense_prompt_embeddings=dense_embeddings,
            multimask_output=multimask_output,
            hq_token_only=hq_token_only,
            interm_embeddings=self.interm_features,
        )

        masks = self.model.postprocess_masks(
            low_res_masks, self.input_size, self.original_size
        )

        if not return_logits:
            masks = masks > self.model.mask_threshold

        return masks, iou_predictions, low_res_masks

    @property
    def device(self) -> Any:
        return self.model.device

    def reset_image(self) -> None:
        self.is_image_set = False
        self.features = None
