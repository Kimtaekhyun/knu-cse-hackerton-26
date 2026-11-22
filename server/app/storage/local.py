"""업로드 이미지 저장소 (로컬 디스크).

키는 MEDIA_DIR 아래의 상대 경로다 (예: captures/<id>/original.jpg). DB에는 키만 저장한다.
docker compose에서는 media 볼륨(/media)에 저장되어 컨테이너를 다시 만들어도 남는다.
"""

import os
import shutil
import tempfile
from pathlib import Path

from app.core.config import get_settings


def path(key: str) -> Path:
    """키의 실제 파일 경로. MEDIA_DIR 밖을 가리키는 키(../ 등)는 거절한다"""
    base = get_settings().media_dir.resolve()  # resolve : Make the path absolute
    full = (base / key).resolve()
    if full == base or not full.is_relative_to(base):
        raise ValueError(f"잘못된 저장소 키예요: {key}")
    return full


def save(key: str, data: bytes) -> None:
    """임시 파일에 끝까지 쓴 뒤 이름을 바꾼다.

    쓰는 도중 서버가 꺼져도 반쯤 쓴 파일이 키 자리에 남지 않는다.
    fsync까지 해서 "저장했다"고 답한 사진이 디스크에 실제로 있게 한다.
    """
    target = path(key)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        dir=target.parent, prefix=".tmp-"
    )  # return value: a pair (fd, name) where fd is returned by os.open, and name is the filename.
    try:
        with os.fdopen(fd, "wb") as file:
            file.write(data)
            file.flush()  # flush : 파이썬 버퍼를 os로 보냄
            os.fsync(file.fileno())  # fsync : os캐시를 실제 디스크에 기록
        os.replace(tmp, target)  # os.replace()는 원자적.
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def exists(key: str) -> bool:
    return path(key).is_file()


def delete(key: str) -> None:
    """파일 하나를 지운다 (카드 하나의 스티커 PNG). 없으면 그냥 넘어간다"""
    path(key).unlink(missing_ok=True)


def delete_tree(prefix: str) -> None:
    """폴더째 지운다 (판서 하나의 원본 · 보정본 · 카드 조각). 없으면 그냥 넘어간다"""
    shutil.rmtree(path(prefix), ignore_errors=True)
