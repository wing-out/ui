#include <QImage>
#include <QBuffer>
#include <QByteArray>

QByteArray convertWebPtoPNG(const QByteArray& webpData) {
    QImage image;
    if (!image.loadFromData(webpData, "WEBP")) {
        return QByteArray();
    }
    QByteArray pngData;
    QBuffer buffer(&pngData);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG");
    return pngData;
}
