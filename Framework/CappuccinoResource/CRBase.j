@import <Foundation/CPObject.j>
@import "CRSupport.j"

var defaultIdentifierKey = @"id",
    classAttributeNames  = [CPDictionary dictionary];

@implementation CappuccinoResource : CPObject
{
    CPString identifier @accessors;
}

// override this method to use a custom identifier for lookups
+ (CPString)identifierKey
{
    return defaultIdentifierKey;
}

// this provides very, very basic pluralization (adding an 's').
// override this method for more complex inflections
+ (CPURL)resourcePath
{
    return [CPURL URLWithString:[self railsName] + @"s"];
}

+ (CPString)railsName
{
    return [[self className] railsifiedString];
}

- (JSObject)attributes
{
    CPLog.warn('This method must be declared in your class to save properly.');
    return {};
}

// switch to this if we can get attribute types
// + (CPDictionary)attributes
// {
//     var array = class_copyIvarList(self),
//         dict  = [[CPDictionary alloc] init];
//
//     for (var i = 0; i < array.length; i++)
//         [dict setObject:array[i].type forKey:array[i].name];
//     return dict;
// }

- (CPArray)attributeNames
{
    if ([classAttributeNames objectForKey:[self className]]) {
        return [classAttributeNames objectForKey:[self className]];
    }

    var attributeNames = [CPArray array],
        klass          = [self class],
        attributes     = class_copyIvarList(klass);

    //retrieve ivar from parent class if any (except if the parent class is CappuccinoResource)
    while((klass = class_getSuperclass(klass)) != CappuccinoResource)
        [attributes addObjectsFromArray:class_copyIvarList(klass)];


    for (var i = 0; i < attributes.length; i++) {
        [attributeNames addObject:attributes[i].name];
    }

    [classAttributeNames setObject:attributeNames forKey:[self className]];

    return attributeNames;
}

- (void)setAttributes:(JSObject)attributes
{
    for (var attribute in attributes) {
        if (attribute == [[self class] identifierKey]) {
            [self setIdentifier:attributes[attribute].toString()];
        } else {
            var attributeName = attribute; //[attribute cappifiedString];
            if ([[self attributeNames] containsObject:attributeName]) {
                var value = attributes[attribute];
                var numberOfArrayElements = 1;
                var objectArray = nil;
                /*
                 * I would much rather retrieve the ivar class than pattern match the
                 * response from Rails, but objective-j does not support this.
                */           
                switch (typeOf(value)) {
                    case "array":
                        numberOfArrayElements = value.length;
                        objectArray = [CPArray array];                        
                    case "object":
                        if(value)
                        {
                            try
                            {
                                for(var i=0;i<numberOfArrayElements;i++)
                                {                               
                                    var resource = [self getResourceForCustomAttribute:attributeName];
                                    if(objectArray)
                                        [resource setAttributes:value[i]];
                                    else
                                        [resource setAttributes:value];
                                        
                                    if(objectArray)
                                        [objectArray addObject:resource]
                                    else
                                        [self setValue:resource forKey:attributeName];
                                }
                                if(objectArray)
                                {
                                    [self setValue:objectArray forKey:attributeName];                                    
                                }
                            }
                            catch(anException)
                            {
                                CPLog.warn(@"An issue occured while translating a JSON attribute("+attributeName+") to a valid object -- " + anException)
                            }
                            break;
                        }
                        break;
                    case "boolean":
                        if (value) {
                            [self setValue:YES forKey:attributeName];
                        } else {
                            [self setValue:NO forKey:attributeName];
                        }
                        break;
                    case "number":
                        [self setValue:value forKey:attributeName];
                        break;
                    case "string":
                        if (value.match(/^\d{4}-\d{2}-\d{2}$/)) {
                            // its a date
                            [self setValue:[CPDate dateWithDateString:value] forKey:attributeName];
                        } else if (value.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)) {
                            // its a datetime
                            [self setValue:[CPDate dateWithDateTimeString:value] forKey:attributeName];
                        } else {
                            // its a string
                            [self setValue:value forKey:attributeName];
                        }
                        break;
                }
            }
        }
    }
}

+ (id)new
{
    return [self new:nil];
}

+ (id)new:(JSObject)attributes
{
    var resource = [[self alloc] init];

    if (!attributes)
        attributes = {};

    [resource setAttributes:attributes];
    return resource;
}

+ (id)create:(JSObject)attributes
{
    var resource = [self new:attributes];
    if ([resource save]) {
        return resource;
    } else {
        return nil;
    }
}

- (BOOL)save
{
    var request = [self resourceWillSave];

    if (!request) {
        return NO;
    }
    
    var response = [CPURLConnection sendAsynchronousRequest:request postTarget:self 
                                                                    postAction:@selector(resourceDidSave:) 
                                                                    postActionOnError:@selector(resourceDidNotSave:)];
}

- (BOOL)destroy
{
    var request = [self resourceWillDestroy];

    if (!request) {
        return NO;
    }

    var response = [CPURLConnection sendAsynchronousRequest:request postTarget:self 
                                                                    postAction:@selector(resourceDidDestroy)
                                                                    postActionOnError:@selector(resourceDidNotDestroy:)];
}

+ (CPArray)all
{
    var request = [self collectionWillLoad];

    if (!request) {
        return NO;
    }
    
    var response = [CPURLConnection sendAsynchronousRequest:request postTarget:self 
                                                                    postAction:@selector(collectionDidLoad:)
                                                                    postActionOnError:@selector(collectionDidNotLoad:)];
}

+ (CPArray)allWithParams:(JSObject)params
{
    var request = [self collectionWillLoad:params];

    var response = [CPURLConnection sendAsynchronousRequest:request postTarget:self 
                                                                    postAction:@selector(collectionDidLoad:)
                                                                    postActionOnError:@selector(collectionDidNotLoad:)];
}

+ (id)find:(CPString)identifier
{
    var request = [self resourceWillLoad:identifier];

    if (!request) {
        return NO;
    }

    var response = [CPURLConnection sendAsynchronousRequest:request postTarget:self 
                                                                    postAction:@selector(resourceDidLoad:)
                                                                    postActionOnError:@selector(resourceDidNotLoad:)];
}

+ (id)findWithParams:(JSObject)params
{
    var collection = [self allWithParams:params];
}

// All the following methods post notifications using their class name
// You can observe these notifications and take further action if desired
+ (CPURLRequest)resourceWillLoad:(CPString)identifier
{
    var path             = [self resourcePath] + "/" + identifier,
        notificationName = [self className] + "ResourceWillLoad";

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"GET"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    return request;
}

+ (id)resourceDidLoad:(CPString)aResponse
{
    var response         = [aResponse toJSON],
        attributes       = response[[self railsName]],
        notificationName = [self className] + "ResourceDidLoad",
        resource         = [self new];

    [resource setAttributes:attributes];
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:resource];
    return resource;
}

+ (CPURLRequest)collectionWillLoad
{
    return [self collectionWillLoad:nil];
}

// can handle a JSObject or a CPDictionary
+ (CPURLRequest)collectionWillLoad:(id)params
{
    var path             = [self resourcePath],
        notificationName = [self className] + "CollectionWillLoad";

    if (params) {
        if (params.isa && [params isKindOfClass:CPDictionary]) {
            path += ("?" + [CPString paramaterStringFromCPDictionary:params]);
        } else {
            path += ("?" + [CPString paramaterStringFromJSON:params]);
        }
    }

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"GET"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];

    return request;
}

+ (CPArray)collectionDidLoad:(CPString)aResponse
{
    var collection       = [aResponse toJSON],
        resourceArray    = [CPArray array],
        notificationName = [self className] + "CollectionDidLoad";

    for (var i = 0; i < collection.length; i++) {
        var resource = collection[i];
        var attributes = resource[[self railsName]];
        [resourceArray addObject:[self new:attributes]];
    }

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:resourceArray];
    return resourceArray;
}

+ (void)collectionDidNotLoad:(CPString)aResponse
{
    [[CPNotificationCenter defaultCenter] postNotificationName:@"CollectionDidNotLoad" object:self];
}

- (CPURLRequest)resourceWillSave
{
    var abstractNotificationName = [self className] + "ResourceWillSave";

    if (identifier) {
        var path             = [[self class] resourcePath] + "/" + identifier,
            notificationName = [self className] + "ResourceWillUpdate";
    } else {
        var path             = [[self class] resourcePath],
            notificationName = [self className] + "ResourceWillCreate";
    }

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];

    [request setHTTPMethod:identifier ? @"PUT" : @"POST"];
    [request setHTTPBody:[CPString JSONFromObject:[self attributes]]];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
    return request;
}

- (void)resourceDidSave:(CPString)aResponse
{
    var response                 = [aResponse toJSON],
        attributes               = response[[[self class] railsName]];
    
    abstractNotificationName = [self className] + "ResourceDidSave";

    if (identifier) {
        var notificationName = [self className] + "ResourceDidUpdate";
    } else {
        var notificationName = [self className] + "ResourceDidCreate";
    }

    [self setAttributes:attributes];
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:self];
}

- (void)resourceDidNotSave:(CPString)aResponse
{
    var abstractNotificationName = [self className] + "ResourceDidNotSave";

    // TODO - do something with errors
    if (identifier) {
        var notificationName = [self className] + "ResourceDidNotUpdate";
    } else {
        var notificationName = [self className] + "ResourceDidNotCreate";
    }

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:aResponse];
    [[CPNotificationCenter defaultCenter] postNotificationName:abstractNotificationName object:aResponse];
}

- (CPURLRequest)resourceWillDestroy
{
    var path             = [[self class] resourcePath] + "/" + identifier,
        notificationName = [self className] + "ResourceWillDestroy";

    if (!path) {
        return nil;
    }

    var request = [CPURLRequest requestJSONWithURL:path];
    [request setHTTPMethod:@"DELETE"];

    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
    return request;
}

-(void)resourceDidDestroy
{
    var notificationName = [self className] + "ResourceDidDestroy";
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
}

-(void)resourceDidNotDestroy
{
    var notificationName = [self className] + "ResourceDidNotDestroy";
    [[CPNotificationCenter defaultCenter] postNotificationName:notificationName object:self];
}

@end