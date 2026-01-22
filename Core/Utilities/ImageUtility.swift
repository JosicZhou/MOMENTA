//
//  ImageUtility.swift
//  AI music
//
//  图片处理工具

import UIKit

struct ImageUtility {
    
    /// 将UIImage转换为base64字符串
    /// - Parameters:
    ///   - image: 要转换的图片
    ///   - maxSize: 最大尺寸（压缩图片以节省token），默认512（更小以节省tokens）
    ///   - quality: JPEG压缩质量（0-1），默认0.5（更低以节省tokens）
    /// - Returns: base64编码的字符串
    static func toBase64(
        image: UIImage,
        maxSize: CGFloat = 512,
        quality: CGFloat = 0.5
    ) -> String? {
        // 调整图片大小
        let resizedImage = resize(image: image, maxSize: maxSize)
        
        // 转换为JPEG数据
        guard let imageData = resizedImage.jpegData(compressionQuality: quality) else {
            return nil
        }
        
        // 转换为base64
        return imageData.base64EncodedString()
    }
    
    /// 调整图片大小（保持宽高比）
    private static func resize(image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        
        // 如果图片已经小于最大尺寸，直接返回
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        // 计算缩放比例
        let widthRatio = maxSize / size.width
        let heightRatio = maxSize / size.height
        let ratio = min(widthRatio, heightRatio)
        
        // 新尺寸
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        // 重新绘制
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
}

