"""사진 해상도 상한(app/services/image_limits.py). 한도를 작게 바꿔 작은 이미지로 확인한다."""

import io

import pytest
from PIL import Image

from app.services import image_limits
from app.services.image_limits import TooManyPixels, UnreadableImage, check_pixels


def encoded(width: int, height: int, fmt: str) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), "white").save(buffer, fmt)
    return buffer.getvalue()


def png(width: int, height: int) -> bytes:
    return encoded(width, height, "PNG")


@pytest.fixture
def limit_100(monkeypatch):
    monkeypatch.setattr(image_limits, "MAX_PIXELS", 100)


def test_returns_size_within_limit(limit_100):
    assert check_pixels(png(10, 10)) == (10, 10)  # 딱 한도까지는 통과


def test_one_pixel_over_limit_is_rejected(limit_100):
    with pytest.raises(TooManyPixels):
        check_pixels(png(101, 1))


def test_pillow_bomb_error_is_too_many_pixels(monkeypatch):
    # Pillow는 자체 한도의 2배를 넘으면 크기를 읽는 단계에서 DecompressionBombError를 낸다
    monkeypatch.setattr(Image, "MAX_IMAGE_PIXELS", 10)
    with pytest.raises(TooManyPixels):
        check_pixels(png(10, 10))


@pytest.mark.parametrize("data", [b"", b"not-an-image", png(4, 4)[:20]])
def test_unreadable_header_is_rejected(data):
    with pytest.raises(UnreadableImage):
        check_pixels(data)


def test_default_limit_allows_app_photos():
    # 앱이 보내는 가장 큰 사진(긴 변 4096 정사각형)과 4K 카메라 프레임은 통과해야 한다
    assert 4096 * 4096 <= image_limits.MAX_PIXELS
    assert 3840 * 2160 <= image_limits.MAX_PIXELS


@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP"])
def test_upload_formats_are_read(fmt):
    assert check_pixels(encoded(8, 6, fmt)) == (8, 6)


@pytest.mark.parametrize("fmt", ["BMP", "GIF", "TIFF"])
def test_other_formats_are_unreadable(fmt):
    # 앱이 보낸 형식 이름(content_type)만 믿지 않고, 받는 세 형식(JPEG · PNG · WEBP)만 연다
    with pytest.raises(UnreadableImage):
        check_pixels(encoded(8, 6, fmt))
