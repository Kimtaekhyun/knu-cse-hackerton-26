"""판서 사진 처리의 OpenCV 부분 (AI 없이 하는 일).

pipeline/note_pipeline.py(test 브랜치)에서 서버에 필요한 부분만 옮겼다.
- 화면 찾아 펴기 (rectify 단계)
- 필기 마스크 · 상자 다듬기 · 손글씨 조각 (interpret 단계)
숫자 정렬 블록 다시 읽기(4-1단계)는 아직 옮기지 않았다.

이미지는 OpenCV 형식(BGR numpy 배열)으로 주고받는다.
"""

import cv2
import numpy as np

# 펜 종류. red: 빨간 펜(프로젝터) / black: 검은 펜(프로젝터) / board: 칠판
Pen = str
# AI에 보내고 보정본으로 저장하는 사진의 긴 변
MAX_SIDE = 1600


class UnreadableImage(ValueError):
    """사진 파일을 이미지로 읽지 못함"""


def decode(data: bytes) -> np.ndarray:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise UnreadableImage("사진을 읽지 못했어요.")
    return image


def encode_jpeg(image: np.ndarray) -> bytes:
    ok, buffer = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        raise ValueError("JPEG로 바꾸지 못했어요.")
    return buffer.tobytes()


def encode_png(image: np.ndarray) -> bytes:
    ok, buffer = cv2.imencode(".png", image)
    if not ok:
        raise ValueError("PNG로 바꾸지 못했어요.")
    return buffer.tobytes()


# ---------- 1. 화면 찾아 펴기 ----------


def order_corners(pts):
    """네 점을 좌상, 우상, 우하, 좌하 순서로 정렬한다."""
    pts = pts.reshape(4, 2).astype(np.float32)
    s = pts.sum(axis=1)
    d = np.diff(pts, axis=1).ravel()
    return np.float32([pts[s.argmin()], pts[d.argmin()], pts[s.argmax()], pts[d.argmax()]])


def looks_like_screen(quad, img_area):
    """화면다운 사각형인지: 충분히 크고, 가로가 더 길고, 많이 기울지 않음."""
    tl, tr, br, bl = quad
    width = (np.linalg.norm(tr - tl) + np.linalg.norm(br - bl)) / 2
    height = (np.linalg.norm(bl - tl) + np.linalg.norm(br - tr)) / 2
    top_angle = abs(np.degrees(np.arctan2(tr[1] - tl[1], tr[0] - tl[0])))
    return (
        cv2.contourArea(quad) > 0.15 * img_area
        and 1.0 < width / max(height, 1) < 2.4
        and top_angle < 20
    )


def find_screen(img):
    """밝은 큰 사각형(화면)의 네 모서리를 찾는다. 못 찾으면 None."""
    scale = 800 / max(img.shape[:2])
    small = cv2.resize(img, None, fx=scale, fy=scale)
    gray = cv2.GaussianBlur(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY), (5, 5), 0)
    img_area = gray.shape[0] * gray.shape[1]

    otsu, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    top = np.percentile(gray, 97)
    best, best_fill = None, 0
    for t in np.linspace(otsu, (otsu + top) / 2, 4):  # 밝기 기준을 바꿔 가며 시도
        bright = (gray > t).astype(np.uint8) * 255
        bright = cv2.morphologyEx(bright, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
        bright = cv2.morphologyEx(bright, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
        contours, _ = cv2.findContours(bright, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            continue
        c = max(contours, key=cv2.contourArea)
        hull = cv2.convexHull(c)
        quad = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True)
        if len(quad) != 4:
            continue
        quad = order_corners(np.array(quad, np.float32))
        if not looks_like_screen(quad, img_area):
            continue
        fill = cv2.contourArea(c) / cv2.contourArea(quad)  # 사각형을 얼마나 꽉 채우는가
        if fill > best_fill:
            best, best_fill = quad, fill
    return None if best is None else best / scale


def straighten(img, corners, margin=0.12):
    """찾은 화면 모서리로 사진을 반듯하게 편다.

    찾은 사각형이 화면 전체가 아니라 슬라이드 안쪽 상자일 수 있고, 판서가 그 밖으로
    삐져나오기도 하므로 사방에 margin 비율만큼 여백을 두고 자른다.
    """
    tl, tr, br, bl = corners
    w = int(max(np.linalg.norm(tr - tl), np.linalg.norm(br - bl)))
    h = int(max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)))
    mx, my = int(w * margin), int(h * margin)
    dst = np.float32([[mx, my], [mx + w, my], [mx + w, my + h], [mx, my + h]])
    return cv2.warpPerspective(
        img,
        cv2.getPerspectiveTransform(corners, dst),
        (w + 2 * mx, h + 2 * my),
        borderMode=cv2.BORDER_REPLICATE,  # 사진 밖으로 나간 부분은 검은색 대신 가장자리로 채움
    )


def shrink(img, max_side=MAX_SIDE):
    """긴 변이 max_side보다 크면 줄인다."""
    k = max_side / max(img.shape[:2])
    if k >= 1:
        return img
    return cv2.resize(img, None, fx=k, fy=k, interpolation=cv2.INTER_AREA)


# ---------- 2. 필기 마스크 ----------


def ink_mask(img, pen: Pen):
    """필기 부분만 255인 마스크. 펜마다 '주변 배경과 얼마나 다른가'를 다르게 본다."""
    b, g, r = [c.astype(np.int16) for c in cv2.split(img)]
    if pen == "red":  # 주변보다 붉은 것 (빨강 - 초록)
        rg = np.clip(r - g + 128, 0, 255).astype(np.uint8)
        diff = rg.astype(np.int16) - cv2.medianBlur(rg, 51).astype(np.int16)
        weak, strong = diff > 6, diff > 14
    else:
        gray = cv2.bilateralFilter(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), 7, 30, 5)
        bg = cv2.medianBlur(gray, 51).astype(np.int16)
        diff = gray.astype(np.int16) - bg if pen == "board" else bg - gray.astype(np.int16)
        weak, strong = diff > 18, diff > 40  # 칠판은 밝은 것, 검은 펜은 어두운 것

    # 약한 선이라도 진한 선과 이어져 있으면 살린다
    count, labels = cv2.connectedComponents(weak.astype(np.uint8), connectivity=8)
    keep = np.zeros(count, bool)
    keep[np.unique(labels[strong])] = True
    keep[0] = False
    return keep[labels].astype(np.uint8) * 255


def remove_long_lines(mask):
    """표 테두리처럼 길게 뻗은 직선을 지운다 (상자를 다듬을 때 멀리 끌려가지 않게)."""
    h, w = mask.shape
    horizontal = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((1, max(1, w // 4)), np.uint8))
    vertical = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((max(1, h // 4), 1), np.uint8))
    lines = cv2.dilate(horizontal | vertical, np.ones((5, 5), np.uint8))
    return cv2.bitwise_and(mask, cv2.bitwise_not(lines))


# ---------- 3. 상자 다듬기 · 손글씨 조각 ----------


def to_pixels(box, w, h):
    """AI의 0~1000 좌표 [ymin, xmin, ymax, xmax]를 픽셀 (x0, y0, x1, y1)로 바꾼다."""
    ymin, xmin, ymax, xmax = box
    x0, x1 = sorted((int(xmin / 1000 * w), int(xmax / 1000 * w)))
    y0, y1 = sorted((int(ymin / 1000 * h), int(ymax / 1000 * h)))
    return max(0, x0), max(0, y0), min(w, x1), min(h, y1)


def refine_box(mask, box, link=0.006, max_grow=0.3, belong=0.4, pad=6):
    """상자에 걸친 필기 덩어리를 끝까지 포함하도록 넓히고, 빈 테두리는 좁힌다.

    link: 이 거리(사진 가로 대비)보다 가까운 선은 같은 글자로 보고 이어 붙인다
    max_grow: 한쪽으로 원래 크기의 이 비율까지만 넓힌다
    belong: 덩어리의 이 비율 이상이 상자 안에 있을 때만 이 상자의 필기로 본다
    """
    h, w = mask.shape
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0

    # 출발점: 상자 안 필기에 딱 맞게 좁힌 상자
    ys, xs = np.nonzero(mask[y0:y1, x0:x1])
    if len(xs) == 0:
        return box
    nx0, ny0, nx1, ny1 = x0 + xs.min(), y0 + ys.min(), x0 + xs.max(), y0 + ys.max()

    # 경계에 걸친 덩어리 중 이 상자의 것은 끝까지 포함
    k = max(3, int(w * link))
    linked = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, max(3, k // 2))))
    _, labels, stats, _ = cv2.connectedComponentsWithStats(linked, connectivity=8)
    lx0, ly0 = max(0, int(x0 - bw * max_grow)), max(0, int(y0 - bh * max_grow))
    lx1, ly1 = min(w, int(x1 + bw * max_grow)), min(h, int(y1 + bh * max_grow))
    for i in np.unique(labels[y0:y1, x0:x1]):
        if i == 0:
            continue
        cx, cy, cw, ch, area = stats[i]
        if (labels[y0:y1, x0:x1] == i).sum() < belong * area:
            continue
        nx0, ny0 = min(nx0, max(cx, lx0)), min(ny0, max(cy, ly0))
        nx1, ny1 = max(nx1, min(cx + cw, lx1)), max(ny1, min(cy + ch, ly1))

    # 이어 붙이느라 부풀린 만큼 실제 필기 경계로 좁힌다
    ys, xs = np.nonzero(mask[ny0:ny1, nx0:nx1])
    if len(xs):
        nx0, nx1 = nx0 + xs.min(), nx0 + xs.max()
        ny0, ny1 = ny0 + ys.min(), ny0 + ys.max()
    return (
        int(max(0, nx0 - pad)),
        int(max(0, ny0 - pad)),
        int(min(w, nx1 + pad)),
        int(min(h, ny1 + pad)),
    )


def card_ink(img, mask, box):
    """카드 상자 부분을 잘라 필기만 보이는 투명 배경 이미지(BGRA)로 만든다."""
    x0, y0, x1, y1 = box
    ink = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    ink[..., :3] = img[y0:y1, x0:x1]
    ink[..., 3] = mask[y0:y1, x0:x1]  # 필기만 보이게
    return ink


def normalized(box, w, h) -> dict[str, float]:
    """픽셀 상자를 보정본 기준 0~1 {x, y, w, h}로 (DB Card.bbox 형식)"""
    x0, y0, x1, y1 = box
    return {
        "x": round(x0 / w, 4),
        "y": round(y0 / h, 4),
        "w": round((x1 - x0) / w, 4),
        "h": round((y1 - y0) / h, 4),
    }
