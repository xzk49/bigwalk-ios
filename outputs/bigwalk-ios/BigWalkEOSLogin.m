#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

// The configured iOS test profile uses this game's existing Device ID login and callbacks. It does not
// synthesize a Steam ticket, PUID, ownership result, or successful EOS response.
void BigWalkProbeEOSDeviceLogin(void) {
    BOOL enabled=[NSProcessInfo.processInfo.arguments containsObject:@"--eos-device-login"] || [NSBundle.mainBundle.infoDictionary[@"BigWalkEOSDeviceLogin"] boolValue];
    fprintf(stderr,"BIGWALK_EOS device_login_diagnostic_enabled=%d\n",enabled);
    if(!enabled)return;
    BOOL authProfile=[NSBundle.mainBundle.infoDictionary[@"BigWalkEOSDeviceAuth"] boolValue];
    fprintf(stderr,"BIGWALK_EOS original_auth_task_device_profile=%d\n",authProfile);
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"GameAssembly.framework/GameAssembly.dylib"];
    void *library=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_NOLOAD);
    void *(*domainGet)(void)=library?dlsym(library,"il2cpp_domain_get"):NULL;
    const void **(*assembliesGet)(void *,size_t *)=library?dlsym(library,"il2cpp_domain_get_assemblies"):NULL;
    const void *(*imageGet)(const void *)=library?dlsym(library,"il2cpp_assembly_get_image"):NULL;
    const char *(*imageName)(const void *)=library?dlsym(library,"il2cpp_image_get_name"):NULL;
    void *(*classGet)(const void *,const char *,const char *)=library?dlsym(library,"il2cpp_class_from_name"):NULL;
    const void *(*methodGet)(void *,const char *,int)=library?dlsym(library,"il2cpp_class_get_method_from_name"):NULL;
    void *(*invoke)(const void *,void *,void **,void **)=library?dlsym(library,"il2cpp_runtime_invoke"):NULL;
    const char *(*className)(void *)=library?dlsym(library,"il2cpp_class_get_name"):NULL;
    void (*fieldValue)(void *,void *,void *)=library?dlsym(library,"il2cpp_field_get_value"):NULL;
    const void *(*methodParam)(const void *,uint32_t)=library?dlsym(library,"il2cpp_method_get_param"):NULL;
    void *(*objectClass)(void *)=library?dlsym(library,"il2cpp_object_get_class"):NULL;
    void *(*unbox)(void *)=library?dlsym(library,"il2cpp_object_unbox"):NULL;
    void *(*fieldGet)(void *,const char *)=library?dlsym(library,"il2cpp_class_get_field_from_name"):NULL;
    void *(*fieldType)(void *)=library?dlsym(library,"il2cpp_field_get_type"):NULL;
    void *(*classFromType)(void *)=library?dlsym(library,"il2cpp_class_from_type"):NULL;
    int (*fieldOffset)(void *)=library?dlsym(library,"il2cpp_field_get_offset"):NULL;
    int (*valueSize)(void *,uint32_t *)=library?dlsym(library,"il2cpp_class_value_size"):NULL;
    void (*staticGet)(void *,void *)=library?dlsym(library,"il2cpp_field_static_get_value"):NULL;
    void (*staticSet)(void *,void *)=library?dlsym(library,"il2cpp_field_static_set_value"):NULL;
    void (*classInit)(void *)=library?dlsym(library,"il2cpp_runtime_class_init"):NULL;
    void (*formatException)(void *,char *,int)=library?dlsym(library,"il2cpp_format_exception"):NULL;
    if(!domainGet||!assembliesGet||!imageGet||!imageName||!classGet||!methodGet||!invoke||!unbox){
        fprintf(stderr,"BIGWALK_EOS device_login_unavailable=reflection_exports\n");
        if(library)dlclose(library);return;
    }
    size_t count=0;const void **assemblies=assembliesGet(domainGet(),&count);void *managerClass=NULL;
    for(size_t i=0;i<count;i++){
        const void *image=imageGet(assemblies[i]);const char *name=imageName(image);
        if(name&&!strcmp(name,"Assembly-CSharp.dll")){managerClass=classGet(image,"","EOSProjectManager");break;}
    }
    const void *instance=managerClass?methodGet(managerClass,"get_Instance",0):NULL;
    const void *connect=managerClass?methodGet(managerClass,"DoDeviceTokenConnect",0):NULL;
    const void *setup=managerClass?methodGet(managerClass,"Setup",0):NULL;
    const void *finishConnect=managerClass?methodGet(managerClass,"Connect",1):NULL;
    const void *setConnectTask=managerClass?methodGet(managerClass,"SetCurrentConnectTask",1):NULL;
    const void *getConnectTask=managerClass?methodGet(managerClass,"get_CurrentConnectTask",0):NULL;
    const void *healthy=managerClass?methodGet(managerClass,"get_ConnectionHealthy",0):NULL;
    const void *connected=managerClass?methodGet(managerClass,"get_IsConnected",0):NULL;
    if(!instance||!connect||!connected){fprintf(stderr,"BIGWALK_EOS device_login_unavailable=game_methods\n");dlclose(library);return;}
    // A failed Steam attempt can leave Nullable<HAuthTicket> with HasValue but
    // the invalid handle. Its unconditional CancelAuthTicket then interrupts
    // genuine EOS callbacks on a host without Steam. Clear only that empty
    // ticket, using the game's actual Invalid constant and IL2CPP field API.
    void *ticketField=NULL;uint32_t invalidTicket=UINT32_MAX;
    if(fieldGet&&fieldType&&classFromType&&fieldOffset&&valueSize&&staticGet&&staticSet&&classInit){
        void *field=fieldGet(managerClass,"_currentAuthTicket");
        void *nullable=field?classFromType(fieldType(field)):NULL;
        void *hasValue=nullable?fieldGet(nullable,"hasValue"):NULL;
        void *value=nullable?fieldGet(nullable,"value"):NULL;
        void *ticket=value?classFromType(fieldType(value)):NULL;
        void *invalid=ticket?fieldGet(ticket,"Invalid"):NULL;
        uint32_t alignment=0;
        if(hasValue&&value&&invalid&&valueSize(nullable,&alignment)==8&&valueSize(ticket,&alignment)==4
           &&fieldOffset(hasValue)==16&&fieldOffset(value)==20){
            classInit(ticket);staticGet(invalid,&invalidTicket);ticketField=field;
            fprintf(stderr,"BIGWALK_EOS invalid_ticket_metadata_verified=1 invalid=%u\n",invalidTicket);
        }else fprintf(stderr,"BIGWALK_EOS invalid_ticket_metadata_verified=0\n");
    }
    const void *eosInstance=NULL;
    for(size_t i=0;i<count;i++){
        void *c=classGet(imageGet(assemblies[i]),"PlayEveryWare.EpicOnlineServices","EOSManager");
        if(c){eosInstance=methodGet(c,"get_Instance",0);
            fprintf(stderr,"BIGWALK_EOS plugin_accessor image=%s available=%d\n",imageName(imageGet(assemblies[i])),eosInstance!=NULL);
            if(eosInstance)break;}
    }
    fprintf(stderr,"BIGWALK_EOS plugin_accessor_found=%d\n",eosInstance!=NULL);
    void *(*valueObject)(void *,void *)=dlsym(library,"il2cpp_field_get_value_object");
    void *(*fields)(void *,void **)=dlsym(library,"il2cpp_class_get_fields");
    const char *(*fieldName)(void *)=dlsym(library,"il2cpp_field_get_name");
    // Unlike field_get_value_object(field, instance), this API takes the
    // instance first. Read the assigned predicate back before reporting it.
    void (*setObject)(void *instance,void *field,void *value)=dlsym(library,"il2cpp_field_set_value_object");
    void *(*newObject)(void *)=dlsym(library,"il2cpp_object_new");
    int32_t (*stringLength)(void *)=dlsym(library,"il2cpp_string_length");
    const uint16_t *(*stringChars)(void *)=dlsym(library,"il2cpp_string_chars");
    uint32_t (*fieldFlags)(void *)=dlsym(library,"il2cpp_field_get_flags");
    NSString *(^managedText)(void *)=^NSString *(void *str){
        return str&&stringLength&&stringChars?[NSString stringWithCharacters:stringChars(str) length:stringLength(str)]:nil;
    };
    __block BOOL setupWaitAdapted=NO;
    __block void *setupTask=NULL;
    // Unity 6000.3 uses pointer-sized GC handles. The audited free function
    // masks the full x0 to find its handle page; uint32_t truncates that page.
    uintptr_t (*gcNew)(void *,bool)=dlsym(library,"il2cpp_gchandle_new");
    void (*gcFree)(uintptr_t)=dlsym(library,"il2cpp_gchandle_free");
    __block uintptr_t setupHandle=0;
    __block BOOL boundLogin=NO, pluginLogged=NO, setupRequested=NO, connectionFinalized=NO;
    __block unsigned ticks=0;__block BOOL requested=NO;__block BOOL ticketLogged=NO;
    [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer){
        ++ticks;
        if(ticks<30)return;
        if(ticks==30)fprintf(stderr,"BIGWALK_EOS checking_original_manager=1\n");
        void *exception=NULL;void *manager=invoke(instance,NULL,NULL,&exception);
        if(exception){char message[1024]={0};if(formatException)formatException(exception,message,sizeof(message));
            fprintf(stderr,"BIGWALK_EOS instance_exception=%s\n",message);[timer invalidate];return;}
        if(manager){
            if(ticketField){
                struct {uint8_t hasValue;uint8_t padding[3];uint32_t value;} ticket={0};
                staticGet(ticketField,&ticket);
                if(!ticketLogged){ticketLogged=YES;fprintf(stderr,"BIGWALK_EOS pending_steam_ticket hasValue=%u invalid=%d\n",ticket.hasValue,ticket.value==invalidTicket);}
                if(ticket.hasValue==1&&ticket.value==invalidTicket){
                    memset(&ticket,0,sizeof(ticket));staticSet(ticketField,&ticket);
                    fprintf(stderr,"BIGWALK_EOS empty_steam_ticket_cleared=1\n");
                }
            }
            // This Mac build's private Device ID helper completes its task but
            // can leave the plugin's local-user selection unset. Bind only a
            // user returned by the live SDK whose actual login status is 2
            // (LoggedIn), through the plugin's existing setter. No IDs or
            // successful statuses are synthesized, and existing users win.
            if(requested&&!boundLogin&&eosInstance&&objectClass){
                void *singleton=invoke(eosInstance,NULL,NULL,&exception);
                if(singleton&&!exception){
                    void *c=objectClass(singleton);
                    if(!pluginLogged){pluginLogged=YES;fprintf(stderr,"BIGWALK_EOS plugin_instance_type=%s\n",className?className(c):"?");}
                    const void *getUser=methodGet(c,"GetProductUserId",0);
                    const void *getConnect=methodGet(c,"GetEOSConnectInterface",0);
                    const void *setUser=methodGet(c,"SetLocalProductUserId",1);
                    void *current=getUser?invoke(getUser,singleton,NULL,&exception):NULL;
                    void *connection=getConnect&&!exception?invoke(getConnect,singleton,NULL,&exception):NULL;
                    if(connection&&!exception&&setUser){
                        void *cc=objectClass(connection);
                        const void *getCount=methodGet(cc,"GetLoggedInUsersCount",0);
                        const void *getAt=methodGet(cc,"GetLoggedInUserByIndex",1);
                        const void *getStatus=methodGet(cc,"GetLoginStatus",1);
                        void *box=getCount?invoke(getCount,connection,NULL,&exception):NULL;
                        int users=box&&!exception?*(int *)unbox(box):0;
                        int currentStatus=0;
                        if(current&&getStatus&&!exception){void *currentArgs[]={current};
                            box=invoke(getStatus,connection,currentArgs,&exception);currentStatus=box&&!exception?*(int *)unbox(box):0;}
                        if(ticks==40||ticks==120)fprintf(stderr,"BIGWALK_EOS sdk_state users=%d selected_user_present=%d selected_status=%d\n",users,current!=NULL,currentStatus);
                        if(currentStatus==2&&!exception){boundLogin=YES;fprintf(stderr,"BIGWALK_EOS plugin_user_already_logged_in=1\n");}
                        if(!boundLogin&&users==1&&getAt&&getStatus&&!exception){
                            int index=0;void *args[]={&index};
                            void *user=invoke(getAt,connection,args,&exception);
                            if(user&&!exception){
                                void *userArgs[]={user};box=invoke(getStatus,connection,userArgs,&exception);
                                int status=box&&!exception?*(int *)unbox(box):0;
                                if(status==2){
                                    invoke(setUser,singleton,userArgs,&exception);
                                    void *readback=!exception?invoke(getUser,singleton,NULL,&exception):NULL;
                                    if(readback&&!exception){
                                        void *readArgs[]={readback};box=invoke(getStatus,connection,readArgs,&exception);
                                        if(box&&!exception&&*(int *)unbox(box)==2){boundLogin=YES;fprintf(stderr,"BIGWALK_EOS server_login_bound_to_game=1 sdk_logged_in_users=1\n");}
                                    }
                                }
                            }
                        }
                    }

                }
                if(exception){char message[1024]={0};if(formatException)formatException(exception,message,sizeof(message));
                    fprintf(stderr,"BIGWALK_EOS login_binding_exception=%s\n",message);exception=NULL;}
            }
            if(boundLogin&&!setupRequested&&setup){
                setupRequested=YES;
                if(authProfile){
                    // Resume the already-running Connect -> Setup chain. A
                    // second Setup leaves the original waiter stranded, and
                    // a subsequent Connect can early-return without health.
                    setupTask=getConnectTask?invoke(getConnectTask,manager,NULL,&exception):NULL;
                    fprintf(stderr,"BIGWALK_EOS original_connect_task_reused=%d exception=%d\n",setupTask!=NULL,exception!=NULL);
                    if(!setupTask&&!exception){
                        fprintf(stderr,"BIGWALK_EOS original_connect_task_missing=1\n");[timer invalidate];return;
                    }
                }else setupTask=invoke(setup,manager,NULL,&exception);
                if(setupTask&&gcNew)setupHandle=gcNew(setupTask,false);
                fprintf(stderr,"BIGWALK_EOS setup_task_root_ready=1 existing_connect=%d exception=%d\n",authProfile,exception!=NULL);
                if(exception){char message[1024]={0};if(formatException)formatException(exception,message,sizeof(message));
                    fprintf(stderr,"BIGWALK_EOS setup_exception=%s\n",message);[timer invalidate];return;}
            }
            // This Mac build waits for Steam initialization inside Setup.
            // Its iOS profile instead waits for the verified, live EOS user.
            // Change only this task's Steam WaitUntil predicate, and allow the
            // original state machine to perform all setup and health updates.
            if(boundLogin&&!setupWaitAdapted&&ticks>=40&&setupTask&&valueObject&&fields&&fieldName&&objectClass&&newObject&&setObject){
                NSMutableArray *queue=[NSMutableArray arrayWithObject:[NSValue valueWithPointer:setupTask]];
                NSMutableSet *seen=[NSMutableSet new];
                for(NSUInteger n=0;n<queue.count&&n<48;n++){
                    void *object=[queue[n] pointerValue];if(!object)continue;
                    NSValue *key=[NSValue valueWithPointer:object];if([seen containsObject:key])continue;[seen addObject:key];
                    void *c=objectClass(object);const char *type=className(c);
                    if(ticks==50)fprintf(stderr,"BIGWALK_EOS setup_task_object index=%lu type=%s\n",(unsigned long)n,type);
                    if(!strcmp(type,"WaitUntil")){
                        void *predicateField=fieldGet(c,"m_Predicate");
                        void *predicate=predicateField?valueObject(predicateField,object):NULL;
                        void *pc=predicate?objectClass(predicate):NULL;
                        const void *getMethod=pc?methodGet(pc,"get_Method",0):NULL;
                        void *error=NULL,*reflection=getMethod?invoke(getMethod,predicate,NULL,&error):NULL;
                        void *rc=reflection&&!error?objectClass(reflection):NULL;
                        const void *getName=rc?methodGet(rc,"get_Name",0):NULL;
                        const void *getDeclaring=rc?methodGet(rc,"get_DeclaringType",0):NULL;
                        NSString *name=getName?managedText(invoke(getName,reflection,NULL,&error)):nil;
                        void *declaring=getDeclaring&&!error?invoke(getDeclaring,reflection,NULL,&error):NULL;
                        const void *getTypeName=declaring&&!error?methodGet(objectClass(declaring),"get_Name",0):NULL;
                        NSString *owner=getTypeName?managedText(invoke(getTypeName,declaring,NULL,&error)):nil;
                        if(ticks==40||ticks==50)fprintf(stderr,"BIGWALK_EOS setup_wait owner=%s method=%s exception=%d\n",owner.UTF8String?:"?",name.UTF8String?:"?",error!=NULL);
                        // WaitUntil holds a compiler-generated static lambda;
                        // require the audited EOSProjectManager Setup closure.
                        BOOL expected=[name isEqualToString:@"<Setup>b__24_0"]&&[owner isEqualToString:@"<>c"];
                        if(expected&&!error){
                            const void *constructor=methodGet(pc,".ctor",2);
                            const void *loginGetter=methodGet(managerClass,"IsUserAlreadyLogin",0);
                            void *target=constructor&&loginGetter?newObject(pc):NULL;
                            if(target){// IL2CPP delegate constructors take a RuntimeMethod pointer,
                                // not its native code address (verified against Func<bool>.ctor).
                                void *function=(void *)loginGetter;void *args[]={manager,&function};
                                invoke(constructor,target,args,&error);
                                if(!error){
                                    setObject(object,predicateField,target);
                                    void *readback=valueObject(predicateField,object);
                                    setupWaitAdapted=readback==target;
                                    const void *keepWaiting=setupWaitAdapted?methodGet(c,"get_keepWaiting",0):NULL;
                                    void *waiting=keepWaiting?invoke(keepWaiting,object,NULL,&error):NULL;
                                    fprintf(stderr,"BIGWALK_EOS setup_wait_assignment_verified=%d keep_waiting=%d exception=%d\n",
                                            setupWaitAdapted,waiting&&!error?*(bool *)unbox(waiting):-1,error!=NULL);
                                    if(setupWaitAdapted&&!error)fprintf(stderr,"BIGWALK_EOS setup_wait_adapted=verified_eos_login\n");
                                }
                            }
                            if(error){char message[1024]={0};if(formatException)formatException(error,message,sizeof(message));
                                fprintf(stderr,"BIGWALK_EOS setup_wait_adapter_exception=%s\n",message);}
                        }
                        continue;
                    }
                    void *it=NULL,*f=NULL;
                    while((f=fields(c,&it))){
                        const char *name=fieldName(f);if(fieldFlags&&(fieldFlags(f)&0x10))continue;
                        if(ticks==50)fprintf(stderr,"BIGWALK_EOS setup_task_field index=%lu name=%s\n",(unsigned long)n,name);
                        if(strstr(name,"source")||strstr(name,"stateMachine")||strstr(name,"enumerator")||strstr(name,"Enumerator")||strstr(name,"current")||strstr(name,"Current")||strstr(name,"u__")||!strcmp(name,"task")||!strcmp(name,"value")){
                            void *child=valueObject(f,object);if(child)[queue addObject:[NSValue valueWithPointer:child]];
                        }
                    }
                }
            }
            void *boxed=invoke(connected,manager,NULL,&exception);
            if(exception){fprintf(stderr,"BIGWALK_EOS connected_getter_exception=1\n");[timer invalidate];return;}
            BOOL isConnected=boxed?*(bool *)unbox(boxed):NO;
            if(ticks==40||ticks==120){
                BOOL setup=NO;
                void *f=fieldGet?fieldGet(managerClass,"_wasSetup"):NULL;
                if(f&&fieldValue)fieldValue(manager,f,&setup);
                fprintf(stderr,"BIGWALK_EOS state was_setup=%d connected=%d\n",setup,isConnected);
                for(NSString *name in @[@"IsUserAlreadyLogin",@"IsConnectAuthPastDeadline",@"get_ConnectionHealthy"]){
                    const void *getter=methodGet(managerClass,name.UTF8String,0);
                    void *error=NULL;void *result=getter?invoke(getter,manager,NULL,&error):NULL;
                    fprintf(stderr,"BIGWALK_EOS state %s=%d exception=%d\n",name.UTF8String,result&&!error?*(bool *)unbox(result):-1,error!=NULL);
                }
            }
            if(isConnected){
                if(!authProfile&&!connectionFinalized&&requested&&finishConnect&&setConnectTask){
                    connectionFinalized=YES;bool skipWarnings=true;void *args[]={&skipWarnings};
                    void *task=invoke(finishConnect,manager,args,&exception);
                    if(task&&!exception&&methodParam&&classFromType&&valueSize&&objectClass){
                        void *expected=classFromType((void *)methodParam(setConnectTask,0));
                        uint32_t alignment=0;
                        if(expected==objectClass(task)&&valueSize(expected,&alignment)==16){
                            void *taskArgs[]={unbox(task)};invoke(setConnectTask,manager,taskArgs,&exception);
                        }else fprintf(stderr,"BIGWALK_EOS connection_task_assignment_skipped=type_mismatch\n");
                    }
                    fprintf(stderr,"BIGWALK_EOS original_connection_task_requested=1 exception=%d\n",exception!=NULL);
                    if(exception){char message[1024]={0};if(formatException)formatException(exception,message,sizeof(message));
                        fprintf(stderr,"BIGWALK_EOS connection_task_exception=%s\n",message);[timer invalidate];return;}
                }
                void *health=healthy?invoke(healthy,manager,NULL,&exception):NULL;
                BOOL isHealthy=health&&!exception?*(bool *)unbox(health):NO;
                if(isHealthy){if(setupHandle&&gcFree){gcFree(setupHandle);setupHandle=0;}fprintf(stderr,"BIGWALK_EOS game_connected=1 connection_healthy=1 device_login_requested=%d\n",requested);[timer invalidate];return;}
            }
            // Let the original Steam attempt finish before the diagnostic.
            if(!requested&&ticks>=30){
                requested=YES;fprintf(stderr,"BIGWALK_EOS original_device_login_requested=1\n");
                invoke(connect,manager,NULL,&exception);
                if(exception){char message[1024]={0};if(formatException)formatException(exception,message,sizeof(message));
                    fprintf(stderr,"BIGWALK_EOS device_login_exception=%s\n",message);[timer invalidate];return;}
            }
        }
        if(ticks>=120){if(setupHandle&&gcFree){gcFree(setupHandle);setupHandle=0;}fprintf(stderr,"BIGWALK_EOS game_connected=0 device_login_requested=%d timeout=60s\n",requested);[timer invalidate];}
    }];
    dlclose(library);
}
