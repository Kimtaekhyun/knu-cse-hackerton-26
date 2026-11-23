"""사진 해상도(가로 × 세로) 상한. 판서 업로드와 처리 워커가 함께 쓴다 (#130).

용량(10MB) 검사만으로는 한 가지 색 PNG처럼 작게 압축된 거대한 사진(예: 3만 × 3만)을 막지 못한다.
그런 사진을 열면 수 GB 메모리를 써서 서버가 죽으므로,
사진 전체를 풀지 않고 헤더만 읽어 크기를 확인한다.
"""

import io

from PIL import Image, UnidentifiedImageError

from app.services.pipeline.vision import UnreadableImage

__all__ = ["FORMATS", "MAX_PIXELS", "TooManyPixels", "UnreadableImage", "check_pixels"]

# 업로드에서 받는 형식만 연다. 앱이 보낸 형식 이름(content_type)만 믿으면
# BMP · TIFF처럼 다른 형식도 Pillow · OpenCV가 열어 처리하게 된다
FORMATS = ("JPEG", "PNG", "WEBP")
# 앱이 보내는 가장 큰 사진은 긴 변 4096 정사각형(약 1,680만 픽셀),
# 4K 카메라 프레임은 약 830만 픽셀이다. 정상 사용자에게 걸리지 않도록 넉넉하게 둔다
MAX_PIXELS = 25_000_000


class TooManyPixels(ValueError):
    """사진 해상도가 상한을 넘음"""


def check_pixels(data: bytes) -> tuple[int, int]:
    """(가로, 세로). 상한을 넘으면 TooManyPixels, 헤더를 읽지 못하거나 받는 형식(FORMATS)이 아니면
    UnreadableImage.

    Image.open은 헤더만 읽고 픽셀은 풀지 않는다. 다만 Pillow 자체 한도(약 1억 8천만 픽셀)를 넘으면
    이 단계에서 DecompressionBombError를 내므로 그것도 TooManyPixels로 바꾼다.
    """
    try:
        with Image.open(io.BytesIO(data), formats=FORMATS) as image:
            width, height = image.size
    except Image.DecompressionBombError as error:
        raise TooManyPixels("사진 해상도가 너무 커요.") from error
    except (UnidentifiedImageError, OSError) as error:
        raise UnreadableImage("사진을 읽지 못했어요.") from error
    if width * height > MAX_PIXELS:
        raise TooManyPixels("사진 해상도가 너무 커요.")
    return width, height
