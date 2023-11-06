// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.

import SwiftUI
import SessionUIKit
import SessionSnodeKit
import SessionUtilitiesKit
import SessionMessagingKit

struct MessageInfoView: View {
    @Environment(\.viewController) private var viewControllerHolder: UIViewController?
    
    @State var index = 1
    @State var showingAttachmentFullScreen = false
    
    static private let cornerRadius: CGFloat = 17
    
    var actions: [ContextMenuVC.Action]
    var messageViewModel: MessageViewModel
    var isMessageFailed: Bool {
        return [.failed, .failedToSync].contains(messageViewModel.state)
    }
    
    var dismiss: (() -> Void)?
    
    var body: some View {
        NavigationView {
            ZStack (alignment: .topLeading) {
                if #available(iOS 14.0, *) {
                    ThemeManager.currentTheme.colorSwiftUI(for: .backgroundPrimary).ignoresSafeArea()
                } else {
                    ThemeManager.currentTheme.colorSwiftUI(for: .backgroundPrimary)
                }
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        // Message bubble snapshot
                        MessageBubble(
                            messageViewModel: messageViewModel
                        )
                        .background(
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .fill(
                                    themeColor: (messageViewModel.variant == .standardIncoming || messageViewModel.variant == .standardIncomingDeleted ?
                                        .messageBubble_incomingBackground :
                                        .messageBubble_outgoingBackground)
                                )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Values.smallSpacing)
                        .padding(.bottom, Values.verySmallSpacing)
                        .padding(.horizontal, Values.largeSpacing)
                        
                        
                        if isMessageFailed {
                            let (image, statusText, tintColor) = messageViewModel.state.statusIconInfo(
                                variant: messageViewModel.variant,
                                hasAtLeastOneReadReceipt: messageViewModel.hasAtLeastOneReadReceipt
                            )
                            
                            HStack(spacing: 6) {
                                if let image: UIImage = image?.withRenderingMode(.alwaysTemplate) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(themeColor: tintColor)
                                        .frame(width: 13, height: 12)
                                }
                                
                                if let statusText: String = statusText {
                                    Text(statusText)
                                        .font(.system(size: Values.verySmallFontSize))
                                        .foregroundColor(themeColor: tintColor)
                                }
                            }
                            .padding(.top, -Values.smallSpacing)
                            .padding(.bottom, Values.verySmallSpacing)
                            .padding(.horizontal, Values.largeSpacing)
                        }
                        
                        if let attachments = messageViewModel.attachments,
                           messageViewModel.cellType == .mediaMessage
                        {
                            let attachment: Attachment = attachments[(index - 1 + attachments.count) % attachments.count]
                            
                            ZStack(alignment: .bottomTrailing) {
                                if attachments.count > 1 {
                                    // Attachment carousel view
                                    SessionCarouselView_SwiftUI(
                                        index: $index,
                                        isOutgoing: (messageViewModel.variant == .standardOutgoing),
                                        contentInfos: attachments
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topLeading
                                    )
                                } else {
                                    MediaView_SwiftUI(
                                        attachment: attachments[0],
                                        isOutgoing: (messageViewModel.variant == .standardOutgoing),
                                        cornerRadius: 0
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topLeading
                                    )
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                                    .padding(.horizontal, Values.largeSpacing)
                                }
                                
                                Button {
                                    self.viewControllerHolder?.present(style: .fullScreen) {
                                        MediaGalleryViewModel.createDetailViewSwiftUI(
                                            for: messageViewModel.threadId,
                                            threadVariant: messageViewModel.threadVariant,
                                            interactionId: messageViewModel.id,
                                            selectedAttachmentId: attachment.id,
                                            options: [ .sliderEnabled ]
                                        )
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .foregroundColor(.init(white: 0, opacity: 0.4))
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 26, height: 26)
                                }
                                .padding(.bottom, Values.smallSpacing)
                                .padding(.trailing, 38)
                            }
                            .padding(.vertical, Values.verySmallSpacing)
                            
                            // Attachment Info
                            ZStack {
                                RoundedRectangle(cornerRadius: Self.cornerRadius)
                                    .fill(themeColor: .backgroundSecondary)
                                    
                                VStack(
                                    alignment: .leading,
                                    spacing: Values.mediumSpacing
                                ) {
                                    InfoBlock(title: "ATTACHMENT_INFO_FILE_ID".localized() + ":") {
                                        Text(attachment.serverId ?? "")
                                            .font(.system(size: Values.mediumFontSize))
                                            .foregroundColor(themeColor: .textPrimary)
                                    }
                                    
                                    HStack(
                                        alignment: .center
                                    ) {
                                        InfoBlock(title: "ATTACHMENT_INFO_FILE_TYPE".localized() + ":") {
                                            Text(attachment.contentType)
                                                .font(.system(size: Values.mediumFontSize))
                                                .foregroundColor(themeColor: .textPrimary)
                                        }
                                        
                                        Spacer()
                                        
                                        InfoBlock(title: "ATTACHMENT_INFO_FILE_SIZE".localized() + ":") {
                                            Text(Format.fileSize(attachment.byteCount))
                                                .font(.system(size: Values.mediumFontSize))
                                                .foregroundColor(themeColor: .textPrimary)
                                        }
                                        
                                        Spacer()
                                    }
                                    HStack(
                                        alignment: .center
                                    ) {
                                        let resolution: String = {
                                            guard let width = attachment.width, let height = attachment.height else { return "N/A" }
                                            return "\(width)×\(height)"
                                        }()
                                        InfoBlock(title: "ATTACHMENT_INFO_RESOLUTION".localized() + ":") {
                                            Text(resolution)
                                                .font(.system(size: Values.mediumFontSize))
                                                .foregroundColor(themeColor: .textPrimary)
                                        }
                                        
                                        Spacer()
                                        
                                        let duration: String = {
                                            guard let duration = attachment.duration else { return "N/A" }
                                            return floor(duration).formatted(format: .videoDuration)
                                        }()
                                        InfoBlock(title: "ATTACHMENT_INFO_DURATION".localized() + ":") {
                                            Text(duration)
                                                .font(.system(size: Values.mediumFontSize))
                                                .foregroundColor(themeColor: .textPrimary)
                                        }
                                        
                                        Spacer()
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                                .padding(.all, Values.largeSpacing)
                            }
                            .frame(maxHeight: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, Values.verySmallSpacing)
                            .padding(.horizontal, Values.largeSpacing)
                        }

                        // Message Info
                        ZStack {
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .fill(themeColor: .backgroundSecondary)
                                
                            VStack(
                                alignment: .leading,
                                spacing: Values.mediumSpacing
                            ) {
                                InfoBlock(title: "MESSAGE_INFO_SENT".localized() + ":") {
                                    Text(messageViewModel.dateForUI.fromattedForMessageInfo)
                                        .font(.system(size: Values.mediumFontSize))
                                        .foregroundColor(themeColor: .textPrimary)
                                }
                                
                                InfoBlock(title: "MESSAGE_INFO_RECEIVED".localized() + ":") {
                                    Text(messageViewModel.receivedDateForUI.fromattedForMessageInfo)
                                        .font(.system(size: Values.mediumFontSize))
                                        .foregroundColor(themeColor: .textPrimary)
                                }
                                
                                if isMessageFailed {
                                    let failureText: String = messageViewModel.mostRecentFailureText ?? "Message failed to send"
                                    InfoBlock(title: "ALERT_ERROR_TITLE".localized() + ":") {
                                        Text(failureText)
                                            .font(.system(size: Values.mediumFontSize))
                                            .foregroundColor(themeColor: .danger)
                                    }
                                }
                                
                                InfoBlock(title: "MESSAGE_INFO_FROM".localized() + ":") {
                                    HStack(
                                        spacing: 10
                                    ) {
                                        let (info, additionalInfo) = ProfilePictureView.getProfilePictureInfo(
                                            size: .message,
                                            publicKey: messageViewModel.authorId,
                                            threadVariant: .contact,    // Always show the display picture in 'contact' mode
                                            customImageData: nil,
                                            profile: messageViewModel.profile,
                                            profileIcon: (messageViewModel.isSenderOpenGroupModerator ? .crown : .none)
                                        )
                                        
                                        let size: ProfilePictureView.Size = .list
                                        
                                        if let info: ProfilePictureView.Info = info {
                                            ProfilePictureSwiftUI(
                                                size: size,
                                                info: info,
                                                additionalInfo: additionalInfo
                                            )
                                            .frame(
                                                width: size.viewSize,
                                                height: size.viewSize,
                                                alignment: .topLeading
                                            )
                                        }
                                        
                                        VStack(
                                            alignment: .leading,
                                            spacing: Values.verySmallSpacing
                                        ) {
                                            if !messageViewModel.authorName.isEmpty  {
                                                Text(messageViewModel.authorName)
                                                    .bold()
                                                    .font(.system(size: Values.mediumLargeFontSize))
                                                    .foregroundColor(themeColor: .textPrimary)
                                            }
                                            Text(messageViewModel.authorId)
                                                .font(.spaceMono(size: Values.mediumFontSize))
                                                .foregroundColor(themeColor: .textPrimary)
                                        }
                                    }
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .topLeading
                            )
                            .padding(.all, Values.largeSpacing)
                        }
                        .frame(maxHeight: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Values.verySmallSpacing)
                        .padding(.horizontal, Values.largeSpacing)

                        // Actions
                        if !actions.isEmpty {
                            ZStack {
                                RoundedRectangle(cornerRadius: Self.cornerRadius)
                                    .fill(themeColor: .backgroundSecondary)
                                
                                VStack(
                                    alignment: .leading,
                                    spacing: 0
                                ) {
                                    ForEach(
                                        0...(actions.count - 1),
                                        id: \.self
                                    ) { index in
                                        let tintColor: ThemeValue = actions[index].isDestructive ? .danger : .textPrimary
                                        Button(
                                            action: {
                                                actions[index].work()
                                                dismiss?()
                                            },
                                            label: {
                                                HStack(spacing: Values.largeSpacing) {
                                                    Image(uiImage: actions[index].icon!.withRenderingMode(.alwaysTemplate))
                                                        .resizable()
                                                        .scaledToFit()
                                                        .foregroundColor(themeColor: tintColor)
                                                        .frame(width: 26, height: 26)
                                                    Text(actions[index].title)
                                                        .bold()
                                                        .font(.system(size: Values.mediumLargeFontSize))
                                                        .foregroundColor(themeColor: tintColor)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                            }
                                        )
                                        .frame(height: 60)
                                        
                                        if index < (actions.count - 1) {
                                            Divider()
                                                .foregroundColor(themeColor: .borderSeparator)
                                        }
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                                .padding(.horizontal, Values.largeSpacing)
                            }
                            .frame(maxHeight: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, Values.verySmallSpacing)
                            .padding(.horizontal, Values.largeSpacing)
                        }
                    }
                }
            }
        }
    }
}

struct MessageBubble: View {
    static private let cornerRadius: CGFloat = 18
    static private let inset: CGFloat = 12
    
    let messageViewModel: MessageViewModel
    
    var bodyLabelTextColor: ThemeValue {
        messageViewModel.variant == .standardOutgoing ?
            .messageBubble_outgoingText :
            .messageBubble_incomingText
    }
    
    var body: some View {
        ZStack {
            switch messageViewModel.cellType {
                case .textOnlyMessage:
                    let maxWidth: CGFloat = (VisibleMessageCell.getMaxWidth(for: messageViewModel) - 2 * Self.inset)
                    
                    VStack(
                        alignment: .leading,
                        spacing: 0
                    ) {
                        if let linkPreview: LinkPreview = messageViewModel.linkPreview {
                            switch linkPreview.variant {
                            case .standard:
                                LinkPreviewView_SwiftUI(
                                    state: LinkPreview.SentState(
                                        linkPreview: linkPreview,
                                        imageAttachment: messageViewModel.linkPreviewAttachment
                                    ),
                                    isOutgoing: (messageViewModel.variant == .standardOutgoing),
                                    maxWidth: maxWidth,
                                    messageViewModel: messageViewModel,
                                    bodyLabelTextColor: bodyLabelTextColor,
                                    lastSearchText: nil
                                )
                                
                            case .openGroupInvitation:
                                OpenGroupInvitationView_SwiftUI(
                                    name: (linkPreview.title ?? ""),
                                    url: linkPreview.url,
                                    textColor: bodyLabelTextColor,
                                    isOutgoing: (messageViewModel.variant == .standardOutgoing))
                            }
                        }
                        else {
                            if let quote = messageViewModel.quote {
                                QuoteView_SwiftUI(
                                    info: .init(
                                        mode: .regular,
                                        authorId: quote.authorId,
                                        quotedText: quote.body,
                                        threadVariant: messageViewModel.threadVariant,
                                        currentUserPublicKey: messageViewModel.currentUserPublicKey,
                                        currentUserBlinded15PublicKey: messageViewModel.currentUserBlinded15PublicKey,
                                        currentUserBlinded25PublicKey: messageViewModel.currentUserBlinded25PublicKey,
                                        direction: (messageViewModel.variant == .standardOutgoing ? .outgoing : .incoming),
                                        attachment: messageViewModel.quoteAttachment
                                    )
                                )
                                .padding(.top, Self.inset)
                                .padding(.horizontal, Self.inset)
                                .padding(.bottom, -Values.smallSpacing)
                            }
                        }
                        
                        if let bodyText: NSAttributedString = VisibleMessageCell.getBodyAttributedText(
                            for: messageViewModel,
                            theme: ThemeManager.currentTheme,
                            primaryColor: ThemeManager.primaryColor,
                            textColor: bodyLabelTextColor,
                            searchText: nil
                        ) {
                            AttributedText(bodyText)
                                .padding(.all, Self.inset)
                        }
                    }
                case .mediaMessage:
                    if let bodyText: NSAttributedString = VisibleMessageCell.getBodyAttributedText(
                        for: messageViewModel,
                        theme: ThemeManager.currentTheme,
                        primaryColor: ThemeManager.primaryColor,
                        textColor: bodyLabelTextColor,
                        searchText: nil
                    ) {
                        AttributedText(bodyText)
                            .padding(.all, Self.inset)
                    }
                case .voiceMessage:
                    if let attachment: Attachment = messageViewModel.attachments?.first(where: { $0.isAudio }){
                        // TODO: Playback Info and check if playing function is needed
                        VoiceMessageView_SwiftUI(attachment: attachment)
                    }
                case .audio, .genericAttachment:
                    if let attachment: Attachment = messageViewModel.attachments?.first {
                        VStack(spacing: Values.smallSpacing) {
                            DocumentView_SwiftUI(attachment: attachment, textColor: bodyLabelTextColor)
                            
                            if let bodyText: NSAttributedString = VisibleMessageCell.getBodyAttributedText(
                                for: messageViewModel,
                                theme: ThemeManager.currentTheme,
                                primaryColor: ThemeManager.primaryColor,
                                textColor: bodyLabelTextColor,
                                searchText: nil
                            ) {
                                ZStack{
                                    AttributedText(bodyText)
                                }
                                .padding(.horizontal, Self.inset)
                                .padding(.bottom, Self.inset)
                            }
                        }
                    }
                default: EmptyView()
            }
        }
    }
}

struct InfoBlock<Content>: View where Content: View {
    let title: String
    let content: () -> Content
    
    private let minWidth: CGFloat = 100
    
    var body: some View {
        VStack(
            alignment: .leading,
            spacing: Values.verySmallSpacing
        ) {
            Text(self.title)
                .bold()
                .font(.system(size: Values.mediumLargeFontSize))
                .foregroundColor(themeColor: .textPrimary)
            self.content()
        }
        .frame(
            minWidth: minWidth,
            alignment: .leading
        )
    }
}

final class MessageInfoViewController: SessionHostingViewController<MessageInfoView> {
    init(actions: [ContextMenuVC.Action], messageViewModel: MessageViewModel) {
        let messageInfoView = MessageInfoView(
            actions: actions,
            messageViewModel: messageViewModel
        )
        
        super.init(rootView: messageInfoView)
        rootView.dismiss = dismiss
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle("message_info_title".localized(), customFontSize: customTitleFontSize)
    }
    
    func dismiss() {
        self.navigationController?.popViewController(animated: true)
    }
}

struct MessageInfoView_Previews: PreviewProvider {
    static var messageViewModel: MessageViewModel {
        let result = MessageViewModel(
            optimisticMessageId: UUID(),
            threadId: "d4f1g54sdf5g1d5f4g65ds4564df65f4g65d54gdfsg",
            threadVariant: .contact,
            threadHasDisappearingMessagesEnabled: false,
            threadOpenGroupServer: nil,
            threadOpenGroupPublicKey: nil,
            threadContactNameInternal: "Test",
            timestampMs: SnodeAPI.currentOffsetTimestampMs(),
            receivedAtTimestampMs: SnodeAPI.currentOffsetTimestampMs(),
            authorId: "d4f1g54sdf5g1d5f4g65ds4564df65f4g65d54gdfsg",
            authorNameInternal: "Test",
            body: "Mauris sapien dui, sagittis et fringilla eget, tincidunt vel mauris. Mauris bibendum quis ipsum ac pulvinar. Integer semper elit vitae placerat efficitur. Quisque blandit scelerisque orci, a fringilla dui. In a sollicitudin tortor. Vivamus consequat sollicitudin felis, nec pretium dolor bibendum sit amet. Integer non congue risus, id imperdiet diam. Proin elementum enim at felis commodo semper. Pellentesque magna magna, laoreet nec hendrerit in, suscipit sit amet risus. Nulla et imperdiet massa. Donec commodo felis quis arcu dignissim lobortis. Praesent nec fringilla felis, ut pharetra sapien. Donec ac dignissim nisi, non lobortis justo. Nulla congue velit nec sodales bibendum. Nullam feugiat, mauris ac consequat posuere, eros sem dignissim nulla, ac convallis dolor sem rhoncus dolor. Cras ut luctus risus, quis viverra mauris.",
            expiresStartedAtMs: nil,
            expiresInSeconds: nil,
            state: .failed,
            isSenderOpenGroupModerator: false,
            currentUserProfile: Profile.fetchOrCreateCurrentUser(),
            quote: nil,
            quoteAttachment: nil,
            linkPreview: nil,
            linkPreviewAttachment: nil,
            attachments: nil
        )
        
        return result
    }
    
    static var actions: [ContextMenuVC.Action] {
        return [
            .reply(messageViewModel, nil, using: Dependencies()),
            .retry(messageViewModel, nil, using: Dependencies()),
            .delete(messageViewModel, nil, using: Dependencies())
        ]
    }
    
    static var previews: some View {
        MessageInfoView(
            actions: actions,
            messageViewModel: messageViewModel
        )
    }
}
