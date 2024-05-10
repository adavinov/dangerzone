###########################################
# Build PyMuPDF

FROM alpine:latest as pymupdf-build

ARG REQUIREMENTS_TXT
ARG MUPDF_TGZ_VERSION="1.24.1"
ARG MUPDF_TGZ_CHECKSUM="5840308280a2be7bd55f5e8a0b5a3ab8839689fa389a48a91433dcabd465be4d"

RUN wget "https://mupdf.com/downloads/archive/mupdf-$MUPDF_TGZ_VERSION-source.tar.gz" \
    && echo "$MUPDF_TGZ_CHECKSUM  mupdf-$MUPDF_TGZ_VERSION-source.tar.gz" | sha256sum -c \
    && tar -xzvf mupdf-$MUPDF_TGZ_VERSION-source.tar.gz

# Install PyMuPDF via hash-checked requirements file
COPY ${REQUIREMENTS_TXT} /tmp/requirements.txt
RUN apk --no-cache add linux-headers g++ linux-headers gcc make python3-dev py3-pip clang-dev
RUN PYMUPDF_SETUP_MUPDF_BUILD="/mupdf-$MUPDF_TGZ_VERSION-source/" \
    pip -vvv install --break-system-packages --require-hashes -r /tmp/requirements.txt


###########################################
# Download Tesseract data

FROM alpine:latest as tessdata-dl
ARG TESSDATA_CHECKSUM=d0e3bb6f3b4e75748680524a1d116f2bfb145618f8ceed55b279d15098a530f9

# Download the trained models from the latest GitHub release of Tesseract, and
# store them under /usr/share/tessdata. This is basically what distro packages
# do under the hood.
#
# Because the GitHub release contains more files than just the trained models,
# we use `find` to fetch only the '*.traineddata' files in the top directory.
#
# Before we untar the models, we also check if the checksum is the expected one.
RUN mkdir /usr/share/tessdata/ && mkdir tessdata && cd tessdata \
    && TESSDATA_VERSION=$(wget -O- -nv https://api.github.com/repos/tesseract-ocr/tessdata_fast/releases/latest \
        | sed -n 's/^.*"tag_name": "\([0-9.]\+\)".*$/\1/p') \
    && wget https://github.com/tesseract-ocr/tessdata_fast/archive/$TESSDATA_VERSION/tessdata_fast-$TESSDATA_VERSION.tar.gz \
    && echo "$TESSDATA_CHECKSUM  tessdata_fast-$TESSDATA_VERSION.tar.gz" | sha256sum -c \
    && tar -xzvf tessdata_fast-$TESSDATA_VERSION.tar.gz -C . \
    && find . -name '*.traineddata' -maxdepth 2 -exec cp {} /usr/share/tessdata/ \; \
    && cd .. && rm -r tessdata


###########################################
# Download H2ORestart
FROM alpine:latest as h2orestart-dl
ARG H2ORESTART_CHECKSUM=5db816a1e57b510456633f55e693cb5ef3675ef8b35df4f31c90ab9d4c66071a
RUN mkdir /libreoffice_ext && cd libreoffice_ext \
    && H2ORESTART_FILENAME=h2orestart.oxt \
    && H2ORESTART_VERSION="v0.5.7" \
    && wget https://github.com/ebandal/H2Orestart/releases/download/$H2ORESTART_VERSION/$H2ORESTART_FILENAME \
    && echo "$H2ORESTART_CHECKSUM  $H2ORESTART_FILENAME" | sha256sum -c \
    && install -dm777 "/usr/lib/libreoffice/share/extensions/"


###########################################
# Dangerzone image

FROM alpine:latest

# Install dependencies
RUN apk --no-cache -U upgrade && \
    apk --no-cache add \
    libreoffice \
    openjdk8 \
    python3 \
    py3-magic \
    font-noto-cjk

COPY --from=pymupdf-build /usr/lib/python3.11/site-packages/fitz/ /usr/lib/python3.11/site-packages/fitz
COPY --from=tessdata-dl /usr/share/tessdata/ /usr/share/tessdata
COPY --from=h2orestart-dl /libreoffice_ext/ /libreoffice_ext

RUN install -dm777 "/usr/lib/libreoffice/share/extensions/"

ENV PYTHONPATH=/opt/dangerzone

RUN mkdir -p /opt/dangerzone/dangerzone
RUN touch /opt/dangerzone/dangerzone/__init__.py
COPY conversion /opt/dangerzone/dangerzone/conversion

# Add the unprivileged user
RUN adduser -s /bin/sh -D dangerzone
USER dangerzone

# /safezone is a directory through which Pixels to PDF receives files
VOLUME /safezone
