//
//  JKRouter.m
//  
//
//  Created by nie on 17/1/11.
//  Copyright © 2017年 localadmin. All rights reserved.
//

#import "JKRouter.h"
#import "UINavigationController+JKRouter.h"

#ifdef DEBUG
#define JKRouterLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#define JKRouterLog(...)
#endif

//******************************************************************************
//*
//*           RouterOptions类
//*           配置跳转时的各种设置
//******************************************************************************

@interface RouterOptions()
//每个页面所对应的moduleID
@property (nonatomic, copy, readwrite) NSString *moduleID;

@end

@implementation RouterOptions

+ (instancetype)options{
    RouterOptions *options = [RouterOptions new];
    options.transformStyle = RouterTransformVCStyleDefault;
    options.animated = YES;
    return options;
}

+ (instancetype)optionsWithModuleID:(NSString *)moduleID{
    RouterOptions *options = [RouterOptions options];
    options.moduleID = moduleID;
    return options;
}

+ (instancetype)optionsWithDefaultParams:(NSDictionary *)params{
    RouterOptions *options = [RouterOptions options];
    options.defaultParams = params;
    return options;
}

+ (instancetype)optionsWithTransformStyle:(RouterTransformVCStyle)tranformStyle{
    RouterOptions *options = [RouterOptions options];
    options.transformStyle = tranformStyle;
    return options;
}

+ (instancetype)optionsWithCreateStyle:(RouterCreateStyle)createStyle{
    RouterOptions *options = [RouterOptions options];
    options.createStyle = createStyle;
    return options;
}

- (instancetype)optionsWithDefaultParams:(NSDictionary *)params{
    self.defaultParams = params;
    return self;
}

@end

//**********************************************************************************
//*
//*           JKRouter类
//*
//**********************************************************************************

@interface JKRouter()

@property (nonatomic, copy, readwrite) NSSet * modules; ///< 存储路由，moduleID信息，权限配置信息
@property (nonatomic,copy) NSArray<NSString *> *routerFileNames; ///< 路由配置信息的json文件名数组

@property (nonatomic,strong) NSSet *urlSchemes; ///< 支持的URL协议集合

@property (nonatomic,copy) NSString *remoteFilePath;///< 从网络上下载的路由配置信息的json文件保存在沙盒中的路径
@end

@implementation JKRouter

//重写该方法，防止外部修改该类的对象
+ (BOOL)accessInstanceVariablesDirectly{
    return NO;
}

static JKRouter *defaultRouter =nil;

/**
 初始化单例
 
 @return JKRouter 的单例对象
 */
+ (instancetype)router{
    
    return [self sharedRouter];
}

+ (instancetype)sharedRouter{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultRouter = [JKRouter new];
    });
    
    return defaultRouter;
}

- (UINavigationController *)topNaVC{
    
    UIViewController *rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    if (self.windowRootVCStyle ==RouterWindowRootVCStyleCustom) {
        UITabBarController *tabBarVC = (UITabBarController *)rootVC;
        UIViewController *vc = tabBarVC.selectedViewController;
        if (![vc isKindOfClass:[UINavigationController class]]) {
            NSAssert(NO, @"tabBarViewController's selectedViewController is not a UINavigationController instance");
        }
        if (vc.presentedViewController && [vc.presentedViewController isKindOfClass:[UINavigationController class]]) {
            return (UINavigationController *)vc.presentedViewController;
        }
        return (UINavigationController *)vc;
    }
    
    if (![rootVC isKindOfClass:[UINavigationController class]]) {
        NSAssert(NO, @"rootVC is not a UINavigationController instance");
    }
    if (rootVC.presentedViewController && [rootVC.presentedViewController isKindOfClass:[UINavigationController class]]) {
        
        return (UINavigationController *)rootVC.presentedViewController;
    }
    return (UINavigationController *)rootVC;
}

+ (void)configWithRouterFiles:(NSArray<NSString *> *)routerFileNames{
    [JKRouter sharedRouter].routerFileNames = routerFileNames;
   NSMutableSet *urlSchemesSet = [NSMutableSet setWithArray:[JKRouterExtension urlSchemes]];
    [urlSchemesSet addObjectsFromArray:[JKRouterExtension specialSchemes]];
    [JKRouter sharedRouter].urlSchemes  = [urlSchemesSet copy];
    
}

+ (void)updateRouterInfoWithFilePath:(NSString*)filePath{
    [JKRouter sharedRouter].remoteFilePath = filePath;
    [JKRouter sharedRouter].modules = nil;
}

- (NSSet *)modules{
    if (!_modules) {
        if (!_remoteFilePath) {
            NSArray *moudulesArr =[JKJSONHandler getModulesFromJsonFile:[JKRouter sharedRouter].routerFileNames];
            _modules = [NSSet setWithArray:moudulesArr];
        }else{
            NSData *data = [NSData dataWithContentsOfFile:_remoteFilePath];
            NSArray *modules = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            if (modules.count>0) {
                _modules = [NSSet setWithArray:modules];
            }
        }
    }
    return _modules;
}

#pragma mark  - - - - the open functions - - - -

+ (void)open:(NSString *)targetClassName{
    [self open:targetClassName params:nil];
}

+ (void)open:(NSString *)targetClassName params:(NSDictionary *)params{
    RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
    [self open:targetClassName options:options];
}

+ (void)open:(NSString *)targetClassName options:(RouterOptions *)options{
    [self open:targetClassName options:options CallBack:nil];
}

+ (void)open:(NSString *)targetClassName optionsWithJSON:(RouterOptions *)options{
    if (!JKSafeStr(targetClassName)) {
        NSAssert(NO, @"targetClassName is nil or targetClassName is not a string");
        return;
    }
    if (!options) {
        options = [RouterOptions options];
    }
    Class targetClass = NSClassFromString(targetClassName);
    if (!targetClass) {
        targetClass = NSClassFromString([NSString stringWithFormat:@"%@.%@",[JKRouterExtension appTargetName],targetClassName]);
    }
    if ([targetClass respondsToSelector:@selector(jkRouterFactoryViewControllerWithJSON:)]) {
        UIViewController *vc = [NSClassFromString(targetClassName) jkRouterFactoryViewControllerWithJSON:options.defaultParams];
        [JKRouter routerViewController:vc options:options];
    }else if ([targetClass jkIsTabBarItemVC]) {
        [JKRouterExtension jkSwitchTabWithVC:targetClassName options:options];//进行tab切换
    }else{
        UIViewController *vc = [targetClass jkRouterViewControllerWithJSON:options.defaultParams];
        //根据配置好的VC，options配置进行跳转
        if (![self routerViewController:vc options:options]) {//跳转失败
            return;
        }
    }
}

+ (void)openSpecifiedVC:(UIViewController *)vc options:(RouterOptions *)options{
    if (!options) {
        options = [RouterOptions options];
    }
     [self routerViewController:vc options:options];
}

+ (void)open:(NSString *)targetClassName options:(RouterOptions *)options CallBack:(void(^)(void))callback{
    
    if (!JKSafeStr(targetClassName)) {
        NSAssert(NO, @"targetClassName is nil or targetClassName is not a string");
        return;
    }
    if (!options) {
        options = [RouterOptions options];
    }
    Class targetClass = NSClassFromString(targetClassName);
    if (!targetClass) {
        targetClass = NSClassFromString([NSString stringWithFormat:@"%@.%@",[JKRouterExtension appTargetName],targetClassName]);
    }
    if ([targetClass respondsToSelector:@selector(jkRouterFactoryViewControllerWithJSON:)]) {
        UIViewController *vc = [NSClassFromString(targetClassName) jkRouterFactoryViewControllerWithJSON:options.defaultParams];
        [JKRouter routerViewController:vc options:options];
    }else if ([targetClass jkIsTabBarItemVC]) {
         [JKRouterExtension jkSwitchTabWithVC:targetClassName options:options];//进行tab切换
    }else{
        UIViewController *vc = [self configVC:targetClassName options:options];
        //根据配置好的VC，options配置进行跳转
        if (![self routerViewController:vc options:options]) {//跳转失败
            return;
        }
    }
    if (callback) {
        callback();
    }
}

+ (void)URLOpen:(NSString *)url{
    [self URLOpen:url extra:nil];
}

+ (void)URLOpen:(NSString *)url extra:(NSDictionary *)extra{
    [self URLOpen:url extra:extra complete:nil];
}

+ (void)URLOpen:(NSString *)url extra:(NSDictionary *)extra complete:(void(^)(id result,NSError *error))completeBlock{
    if(!url){
        JKRouterLog(@"url 不存在");
        if(completeBlock){
            NSError * error = [NSError errorWithDomain:@"JKRouter" code:-100 userInfo:@{@"message":@"url不存在"}];
            completeBlock(nil,error);
        }
        return;
    }
    url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *targetURL = [NSURL URLWithString:url];
    NSString *scheme =targetURL.scheme;
    if (![[JKRouter sharedRouter].urlSchemes containsObject:scheme]) {
        JKRouterLog(@"app不支持该协议的跳转");
        if(completeBlock){
            NSError * error = [NSError errorWithDomain:@"JKRouter" code:-101 userInfo:@{@"message":@"app不支持该协议的跳转"}];
            completeBlock(nil,error);
        }
        return;
    }
    if (![JKRouterExtension safeValidateURL:url]) {
        JKRouterLog(@"url无法通过安全校验");
        if(completeBlock){
            NSError * error = [NSError errorWithDomain:@"JKRouter" code:-1-2 userInfo:@{@"message":@"url无法通过安全校验"}];
            completeBlock(nil,error);
        }
        return;
    }
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        
        [self httpOpen:targetURL extra:extra];
        return;
    }
    if ([scheme isEqualToString:@"file"]) {
        [self jumpToSandBoxWeb:url extra:extra];
        return;
    }
    if ([scheme isEqualToString:@"itms-apps"]) {
        [self openExternal:targetURL];
        return;
    }
    if ([[JKRouterExtension specialSchemes] containsObject:scheme]) {
        [JKRouterExtension openURLWithSpecialSchemes:targetURL extra:extra complete:completeBlock];
        return;
    }
    
    NSString *moduleID = [targetURL.path substringFromIndex:1];
    NSString *type = [JKJSONHandler getTypeWithModuleID:moduleID];
    if ([type isEqualToString:[JKRouterExtension jkModuleTypeViewControllerKey]]) {
        NSString *vcClassName = [JKJSONHandler getHomePathWithModuleID:moduleID];
        if ([NSClassFromString(vcClassName) isSubclassOfClass:[UIViewController class]]) {
            NSString *parameterStr = [[targetURL query] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSMutableDictionary *dic = nil;
            if (JKSafeStr(parameterStr)) {
                dic = [self convertUrlStringToDictionary:parameterStr];
                [dic addEntriesFromDictionary:extra];
            }else{
                dic = [NSMutableDictionary dictionaryWithDictionary:extra];
            }
            RouterOptions *options = [RouterOptions options];
            options.defaultParams = [dic copy];
            //执行页面的跳转
            [self open:vcClassName optionsWithJSON:options];
        }else{//进行特殊路由跳转的操作
            [JKRouterExtension otherActionsWithActionType:type URL:targetURL extra:extra complete:completeBlock];
        }
    }else if ([type isEqualToString:[JKRouterExtension  jkModuleTypeFactoryKey]]){
       NSString *factoryClassName = [JKJSONHandler getHomePathWithModuleID:moduleID];
        Class targetClass = NSClassFromString(factoryClassName);
        if (!targetClass) {
            targetClass = NSClassFromString([NSString stringWithFormat:@"%@.%@",[JKRouterExtension appTargetName],factoryClassName]);
        }
        NSString *parameterStr = [[targetURL query] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSMutableDictionary *dic = nil;
        if (JKSafeStr(parameterStr)) {
            dic = [self convertUrlStringToDictionary:parameterStr];
            [dic addEntriesFromDictionary:extra];
        }else{
            dic = [NSMutableDictionary dictionaryWithDictionary:extra];
        }
        RouterOptions *options = [RouterOptions options];
        options.defaultParams = [dic copy];
        if ([targetClass respondsToSelector:@selector(jkRouterFactoryViewControllerWithJSON:)]) {
            UIViewController *vc =   [targetClass jkRouterFactoryViewControllerWithJSON:options.defaultParams];
            [JKRouter routerViewController:vc options:options];
        }
        
    }
    else{
        //进行非路由跳转的操作
        [JKRouterExtension otherActionsWithActionType:type URL:targetURL extra:extra complete:completeBlock];
    }
    
}

+ (void)httpOpen:(NSURL *)url extra:(NSDictionary *)extra{
    NSString *parameterStr = [[url query] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (JKSafeStr(parameterStr)) {
        NSMutableDictionary *dic = [self convertUrlStringToDictionary:parameterStr];
        if (JKSafeDic(dic) &&[[dic objectForKey:[JKRouterExtension jkBrowserOpenKey]] isEqualToString:@"1"]) {//在safari打开网页
            [self openExternal:[self url:url removeQueryKeys:@[[JKRouterExtension jkBrowserOpenKey]]]];
        }else{
            NSString *key1 = [JKRouterExtension jkWebTypeKey];
            NSString *key2 = [JKRouterExtension jkBrowserOpenKey];
            url = [self url:url removeQueryKeys:@[key1,key2]];
            NSDictionary *tempParams = @{[JKRouterExtension jkWebURLKey]:url.absoluteString};
            NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithDictionary:tempParams];
            [params addEntriesFromDictionary:extra];
            RouterOptions *options = [RouterOptions optionsWithDefaultParams:[params copy]];
            
            NSInteger webType = [dic jk_integerForKey:[JKRouterExtension jkWebTypeKey]];
            NSString *webContainerName = [[JKRouterExtension jkWebVCClassNames] jk_stringWithIndex:webType];
            [self open:webContainerName optionsWithJSON:options];
        }
    }else{
        NSDictionary *tempParams = @{[JKRouterExtension jkWebURLKey]:url.absoluteString};
        NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithDictionary:tempParams];
        [params addEntriesFromDictionary:extra];
        RouterOptions *options = [RouterOptions optionsWithDefaultParams:[params copy]];
        NSString *webContainerName = [[JKRouterExtension jkWebVCClassNames] jk_stringWithIndex:0];
        [self open:webContainerName optionsWithJSON:options];
    }
    
}

+ (void)jumpToSandBoxWeb:(NSString *)url extra:(NSDictionary *)extra{
    if (!JKSafeStr(url)) {
        JKRouterLog(@"路径不存在");
        return;
    }
     NSDictionary *urlParams = [self convertUrlStringToDictionary:url];
    url = [self urlStr:url removeQueryKeys:@[[JKRouterExtension jkWebTypeKey]]];
    NSDictionary *params = @{[JKRouterExtension jkWebURLKey]:url};
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] initWithDictionary:params];
    [dic addEntriesFromDictionary:extra];
     RouterOptions *options = [RouterOptions optionsWithDefaultParams:[dic copy]];
    NSInteger webType = [urlParams jk_integerForKey:[JKRouterExtension jkWebTypeKey]];
    NSString *webContainerName = [[JKRouterExtension jkWebVCClassNames] jk_stringWithIndex:webType];
    [self open:webContainerName optionsWithJSON:options];
}

+ (void)openExternal:(NSURL *)targetURL {
    if ([targetURL.scheme isEqualToString:@"http"] ||[targetURL.scheme isEqualToString:@"https"] || [targetURL.scheme isEqualToString:@"itms-apps"]) {
        [[UIApplication sharedApplication] openURL:targetURL];
    }else{
        NSAssert(NO, @"请输入app支持的协议的url地址");
    }
}

#pragma mark  - - - - the pop functions - - - -

+ (void)pop{
    [self pop:YES];
}

+ (void)pop:(BOOL)animated{
    [self pop:nil :animated];
}

+ (void)pop:(NSDictionary *)params :(BOOL)animated{
    NSArray *vcArray = [JKRouter sharedRouter].topNaVC.viewControllers;
    NSUInteger count = vcArray.count;
    UIViewController *vc= nil;
    RouterOptions *options = nil;
    if (params) {
        options = [RouterOptions optionsWithDefaultParams:params];
    }
    if (vcArray.count>1) {
        vc = vcArray[count-2];
    }else{
        //已经是根视图，不再执行pop操作  可以执行dismiss操作
        if ([JKRouter sharedRouter].topNaVC.isPresented) {
            [[JKRouter sharedRouter].topNaVC dismissViewControllerAnimated:animated completion:^{
                UIViewController *newVC= [JKRouter sharedRouter].topNaVC.topViewController;
                [self configTheVC:newVC options:options];
                [newVC viewWillAppear:animated];
            }];
        }else{
         [self popToSpecifiedVC:nil options:options animated:YES];
        }
        
        return;
    }
    
    [self popToSpecifiedVC:vc options:options animated:YES];
}


+ (void)popToSpecifiedVC:(UIViewController *)vc{
    [self popToSpecifiedVC:vc animated:YES];
}

+ (void)popToSpecifiedVC:(UIViewController *)vc animated:(BOOL)animated{
    [self popToSpecifiedVC:vc options:nil animated:YES];
}

+ (void)popToSpecifiedVC:(UIViewController *)vc options:(RouterOptions *)options animated:(BOOL)animated{
    if (!vc) {
        if ([JKRouter sharedRouter].topNaVC.presentationController &&[JKRouter sharedRouter].topNaVC.presentedViewController) {
            [[JKRouter sharedRouter].topNaVC dismissViewControllerAnimated:animated completion:^{
                [self configTheVC:[JKRouter sharedRouter].topNaVC.topViewController options:options];
            }];
        }
        return;
    }
    else {
        if (vc) {
            [self configTheVC:vc options:options];
            [[JKRouter sharedRouter].topNaVC popToViewController:vc animated:animated];
        }
    }
}

+ (void)popWithSpecifiedModuleID:(NSString *)moduleID{
    [self popWithSpecifiedModuleID:moduleID :nil :YES];
}

+ (void)popWithSpecifiedModuleID:(NSString *)moduleID :(NSDictionary *)params :(BOOL)animated{
    NSArray *vcArray  = [JKRouter sharedRouter].topNaVC.viewControllers;
        for (NSInteger i = vcArray.count-1; i>0; i--) {
            UIViewController *vc = vcArray[i];
            if ([vc.moduleID isEqualToString:moduleID]) {
                RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
                [self configTheVC:vc options:options];
                [self popToSpecifiedVC:vc animated:animated];
            }
        }
}

+ (void)popWithStep:(NSInteger)step{
    [self popWithStep:step :YES];
}

+ (void)popWithStep:(NSInteger)step :(BOOL)animated{
    [self popWithStep:step params:nil animated:animated];
}

+ (void)popWithStep:(NSInteger)step params:(NSDictionary *)params animated:(BOOL)animated{
    NSArray *vcArray = [JKRouter sharedRouter].topNaVC.viewControllers;
    UIViewController *vc= nil;
    if (step>0) {
        if([JKRouter sharedRouter].topNaVC.viewControllers.count>step){
            NSUInteger count = vcArray.count;
            vc = vcArray[(count-1) - step];
            RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
            [self configTheVC:vc options:options];
            [self popToSpecifiedVC:vc animated:animated];
        }else if([JKRouter sharedRouter].topNaVC.viewControllers.count == step){
            UIViewController *vc= nil;
            vc = vcArray[0];
            RouterOptions *options = [RouterOptions optionsWithDefaultParams:params];
            [self configTheVC:vc options:options];
            [self popToSpecifiedVC:vc animated:animated];
        }else{
            JKRouterLog(@"step不在正常范围 执行popToRootViewController操作");
            //已经是根视图，不再执行pop操作  可以执行dismiss操作
            vc = vcArray[0];
            [self popToSpecifiedVC:vc animated:animated];
        }
    }
    
}

#pragma mark  - - - - the tool functions - - - -

+ (void)replaceCurrentViewControllerWithTargetVC:(UIViewController *)targetVC{
    NSArray *viewControllers = [JKRouter sharedRouter].topNaVC.viewControllers;
    NSMutableArray *vcArray = [NSMutableArray arrayWithArray:viewControllers];
    [vcArray replaceObjectAtIndex:viewControllers.count-1 withObject:targetVC];
    [[JKRouter sharedRouter].topNaVC setViewControllers:[vcArray copy] animated:YES];
}

//为ViewController 的属性赋值
+ (UIViewController *)configVC:(NSString *)vcClassName options:(RouterOptions *)options {

    Class targetClass = NSClassFromString(vcClassName);
    if (!targetClass) {
        targetClass = NSClassFromString([NSString stringWithFormat:@"%@.%@",[JKRouterExtension appTargetName],vcClassName]);
    }
    UIViewController *vc = [targetClass jkRouterViewController];
    [vc setValue:options.moduleID forKey:[JKRouterExtension JKRouterModuleIDKey]];
    [JKRouter configTheVC:vc options:options];
    return vc;
}

/**
 对于已经创建的vc进行赋值操作

 @param vc 对象
 @param options 跳转的各种设置
 */
+ (void)configTheVC:(UIViewController *)vc options:(RouterOptions *)options{
    if (!options) {
        return;
    }
    if (JKSafeDic(options.defaultParams)) {
        NSArray *propertyNames = [options.defaultParams allKeys];
        for (NSString *key in propertyNames) {
            id value =options.defaultParams[key];
            [vc setValue:value forKey:key];
        }
    }
}

//将url ？后的字符串转换为NSDictionary对象
+ (NSMutableDictionary *)convertUrlStringToDictionary:(NSString *)urlString{
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];
    NSArray *parameterArr = [urlString componentsSeparatedByString:@"&"];
    for (NSString *parameter in parameterArr) {
        NSArray *parameterBoby = [parameter componentsSeparatedByString:@"="];
        if (parameterBoby.count == 2) {
            [dic setObject:parameterBoby[1] forKey:parameterBoby[0]];
        }else
        {
            JKRouterLog(@"参数不完整");
        }
    }
    return dic;
}

+ (NSURL *)url:(NSURL *)url appendParameter:(NSDictionary *)parameter{
   NSString *urlString = [self urlStr:url.absoluteString appendParameter:parameter];
    return [NSURL URLWithString:urlString];
}

+ (NSString *)urlStr:(NSString *)urlStr appendParameter:(NSDictionary *)parameter{
    
    //[urlStr hasSuffix:@"&"]?[urlStr stringByReplacingOccurrencesOfString:@"&" withString:@""]:urlStr;
    if ([urlStr hasSuffix:@"&"]) {
        urlStr = [urlStr substringToIndex:urlStr.length-1];
    }
    if (!([parameter allKeys].count>0)) {
        return urlStr;
    }
    NSString *firstSeperator = @"";
    if (![urlStr containsString:@"?"]) {
        urlStr = [NSString stringWithFormat:@"%@?",urlStr];
    }else if ([urlStr containsString:@"?"] && ![urlStr hasSuffix:@"?"]){
        firstSeperator = @"&";
    }
    NSString *query = firstSeperator;
    for (NSString *key in parameter.allKeys) {
        NSString *value = [parameter jk_stringForKey:key];
        if ([query hasSuffix:@"&"]) {
            query = [NSString stringWithFormat:@"%@%@=%@",query,key,value];
        }else{
            if (query.length>0) {
                query = [NSString stringWithFormat:@"%@&%@=%@",query,key,value];
            }else{
             query = [NSString stringWithFormat:@"%@=%@",key,value];
            }
        }
    }
    
    return [NSString stringWithFormat:@"%@%@",urlStr,query];
}

+ (NSURL *)url:(NSURL*)url removeQueryKeys:(NSArray <NSString *>*)keys{
    NSString *urlString = [self urlStr:url.absoluteString removeQueryKeys:keys];
    return [NSURL URLWithString:urlString];
}

+ (NSString *)urlStr:(NSString *)urlStr removeQueryKeys:(NSArray <NSString *>*)keys{
    if (!(keys.count>0)) {
        NSAssert(NO, @"urlStr:removeQueryKeys: keys cannot be nil");
    }
    NSArray *tempArray = [urlStr componentsSeparatedByString:@"?"];
    NSString *query = nil;
    if (tempArray.count==2) {
        query = tempArray.lastObject;
    }
    NSDictionary *tempParameter = [self convertUrlStringToDictionary:query];
    NSMutableDictionary *parameter = [[NSMutableDictionary alloc] initWithDictionary:tempParameter];
    for (NSString *key in keys) {
        [parameter removeObjectForKey:key];
    }
    
    NSString *baseUrl = tempArray.firstObject;
    if (parameter.count ==0) {
        return baseUrl;
    }
    NSString *urlString= [self urlStr:baseUrl appendParameter:parameter];
    return urlString;
}

//根据相关的options配置，进行跳转
+ (BOOL)routerViewController:(UIViewController *)vc options:(RouterOptions *)options{
    if (![[vc class]  validateTheAccessToOpenWithOptions:options]) {//权限不够进行别的操作处理
        //根据具体的权限设置决定是否进行跳转，如果没有权限，跳转中断，进行后续处理
        [[vc class] handleNoAccessToOpenWithOptions:options];
        return NO;
    }
    if ([JKRouter sharedRouter].topNaVC.presentationController &&[JKRouter sharedRouter].topNaVC.presentedViewController && ![[JKRouter sharedRouter].topNaVC.presentedViewController isKindOfClass:[UINavigationController class]]) {
        [[JKRouter sharedRouter].topNaVC dismissViewControllerAnimated:NO completion:nil];
    }
    if (options.transformStyle == RouterTransformVCStyleDefault) {
        options.transformStyle =  [vc jkRouterTransformStyle];
    }
    switch (options.transformStyle) {
        case RouterTransformVCStylePush:
            {
                [self _openWithPushStyle:vc options:options];
            }
            break;
            case RouterTransformVCStylePresent:
            {
                [self _openWithPresentStyle:vc options:options];
            }
            break;
            case RouterTransformVCStyleOther:
            {
                [self _openWithOtherStyle:vc options:options];
            }
            break;
            
        default:
            break;
    }
    return NO;
}

+ (BOOL)_openWithPushStyle:(UIViewController *)vc options:(RouterOptions *)options{
    if (options.createStyle==RouterCreateStyleNew) {
        [[JKRouter sharedRouter].topNaVC pushViewController:vc animated:options.animated];
    }else if (options.createStyle==RouterCreateStyleReplace) {
        
        NSArray *viewControllers = [JKRouter sharedRouter].topNaVC.viewControllers;
        NSMutableArray *vcArray = [NSMutableArray arrayWithArray:viewControllers];
        [vcArray replaceObjectAtIndex:viewControllers.count-1 withObject:vc];
        [[JKRouter sharedRouter].topNaVC setViewControllers:[vcArray copy] animated:YES];
    }else if (options.createStyle==RouterCreateStyleRefresh) {
        UIViewController *currentVC = [JKRouter sharedRouter].topNaVC.topViewController;
        if ([[currentVC class] isKindOfClass:[vc class]]) {
            [currentVC jkRouterRefresh];
        }else{
             [[JKRouter sharedRouter].topNaVC pushViewController:vc animated:options.animated];
        }
    }
    return YES;
}

+ (BOOL)_openWithPresentStyle:(UIViewController *)vc options:(RouterOptions *)options{
    if (options.createStyle == RouterCreateStyleNewWithNaVC) {
        UINavigationController *naVC = [[UINavigationController alloc] initWithRootViewController:vc];
        naVC.isPresented = YES;
        [[JKRouter sharedRouter].topNaVC presentViewController:naVC animated:options.animated completion:nil];
    }else{
      [[JKRouter sharedRouter].topNaVC presentViewController:vc animated:options.animated completion:nil];
    }
    
    return YES;
}

+ (BOOL)_openWithOtherStyle:(UIViewController *)vc options:(RouterOptions *)options{
    [vc jkRouterSpecialTransformWithNaVC:[JKRouter sharedRouter].topNaVC];
    return YES;
}


@end
