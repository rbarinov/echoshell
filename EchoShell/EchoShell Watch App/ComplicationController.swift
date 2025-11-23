//
//  ComplicationController.swift
//  EchoShell Watch App
//
//  Created by Roman Barinov on 2025.11.20.
//

#if os(watchOS)
import ClockKit

@objc(ComplicationController)
class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Complication Configuration
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "complication",
                displayName: "Audio Recorder",
                supportedFamilies: CLKComplicationFamily.allCases
            )
        ]
        handler(descriptors)
    }
    
    func handleSharedComplicationDescriptors(_ complicationDescriptors: [CLKComplicationDescriptor]) {
        // Do any necessary work to support these newly shared complication descriptors
    }
    
    // MARK: - Timeline Configuration
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Создаем простой template с иконкой микрофона
        let template = createTemplate(for: complication.family)
        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        handler(nil)
    }
    
    // MARK: - Sample Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        let template = createTemplate(for: complication.family)
        handler(template)
    }
    
    // MARK: - Helper Methods
    
    private func createTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate {
        switch family {
        case .modularSmall:
            return CLKComplicationTemplateModularSmallSimpleImage(
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "Audio Recorder"),
                body1TextProvider: CLKSimpleTextProvider(text: "Tap to record")
            )
            
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: CLKSimpleTextProvider(text: "🎤"),
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: CLKSimpleTextProvider(text: "🎤 Record"),
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallSimpleImage(
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeSimpleImage(
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerCircularImage(
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularImage(
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
            )
            
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKTextProvider(format: "Audio Recorder"),
                body1TextProvider: CLKTextProvider(format: "Tap to record")
            )
            
        case .graphicBezel:
            return CLKComplicationTemplateGraphicBezelCircularText(
                circularTemplate: CLKComplicationTemplateGraphicCircularImage(
                    imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
                ),
                textProvider: CLKTextProvider(format: "Audio Recorder")
            )
            
        case .graphicExtraLarge:
            if #available(watchOS 7.0, *) {
                return CLKComplicationTemplateGraphicExtraLargeCircularImage(
                    imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "mic.fill")!)
                )
            } else {
                return CLKComplicationTemplateModularSmallSimpleImage(
                    imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
                )
            }
            
        @unknown default:
            return CLKComplicationTemplateModularSmallSimpleImage(
                imageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "mic.fill")!)
            )
        }
    }
}
#endif

