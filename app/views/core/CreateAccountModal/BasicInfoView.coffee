ModalView = require 'views/core/ModalView'
AuthModal = require 'views/core/AuthModal'
template = require 'templates/core/create-account-modal/basic-info-view'
forms = require 'core/forms'
errors = require 'core/errors'
User = require 'models/User'
State = require 'models/State'

module.exports = class BasicInfoView extends ModalView
  id: 'basic-info-view'
  template: template

  events:
    'input input[name="name"]': ->
      @nameUniquePromise = null
      @onNameChange()
    'click .back-button': -> @trigger 'nav-back'
    'submit form': (e) ->
      e.preventDefault()
      data = forms.formToObject(e.currentTarget)
      valid = @checkBasicInfo(data)
      # TODO: This promise logic is super weird and confusing. Rewrite.
      @checkNameUnique() unless @nameUniquePromise
      @nameUniquePromise.then ->
        @nameUniquePromise = null
      if valid
        @onSubmitForm(e)
    'click .login-link': ->
      @openModalView(new AuthModal())
    'click .use-suggested-name-link': (e) ->
      @$('input[name="name"]').val(@state.get('suggestedName'))
      forms.clearFormAlerts(@$el.find('input[name="name"]').closest('.form-group').parent())
    'click #facebook-signup-btn': 'onClickSsoSignupButton'
    'click #gplus-signup-btn': 'onClickSsoSignupButton'

  initialize: ({ @sharedState } = {}) ->
    @state = new State {
      suggestedName: null
    }
    @onNameChange = _.debounce(_.bind(@checkNameUnique, @), 500)
    @listenTo @sharedState, 'change:facebookEnabled', -> @renderSelectors('.auth-network-logins')
    @listenTo @sharedState, 'change:gplusEnabled', -> @renderSelectors('.auth-network-logins')

  checkNameUnique: ->
    name = $('input[name="name"]', @$el).val()
    return forms.clearFormAlerts(@$('input[name="name"]').closest('.form-group').parent()) if name is ''
    @nameUniquePromise = new Promise((resolve, reject) => User.getUnconflictedName name, (newName) =>
      if name is newName
        @state.set { suggestedName: null }
        @clearNameError()
        resolve true
      else
        @state.set { suggestedName: newName }
        @setNameError(newName)
        resolve false
    )

  clearNameError: ->
    forms.clearFormAlerts(@$('input[name="name"]').closest('.form-group').parent())

  setNameError: (newName) ->
    @clearNameError()
    forms.setErrorToProperty @$el, 'name', "Username already taken!<br>Try <a class='use-suggested-name-link'>#{newName}</a>?" # TODO: Translate!
    
    # jqxhr = User.getUnconflictedName name, (newName) =>
    #   forms.clearFormAlerts(@$el)
    #   if name is newName
    #     @suggestedName = undefined
    #     @state.set { nameUnique: true }
    #   else
    #     @suggestedName = newName
    #     forms.setErrorToProperty @$el, 'name', "Username already taken!<br>Try <a class='use-suggested-name-link'>#{newName}</a>?" # TODO: Translate!
    #     @state.set { nameUnique: false }
    
  checkBasicInfo: (data) ->
    # TODO: Move this to somewhere appropriate
    tv4.addFormat({
      'email': (email) ->
        if forms.validateEmail(email)
          return null
        else
          return {code: tv4.errorCodes.FORMAT_CUSTOM, message: "Please enter a valid email address."}
    })
    
    forms.clearFormAlerts(@$el)
    res = tv4.validateMultiple data, @formSchema()
    forms.applyErrorsToForm(@$('form'), res.errors) unless res.valid
    return res.valid
  
  formSchema: ->
    type: 'object'
    properties:
      email: User.schema.properties.email
      name: User.schema.properties.name
      password: User.schema.properties.password
    required: ['email', 'name', 'password'].concat (if @sharedState.get('path') is 'student' then ['firstName', 'lastName'] else [])

  onSubmitForm: (e) ->
    e.preventDefault()

    attrs = forms.formToObject @$el
    # attrs.name = @state.get('suggestedName') if @state.get('suggestedName')
    _.defaults attrs, me.pick([
      'preferredLanguage', 'testGroupNumber', 'dateCreated', 'wizardColor1',
      'name', 'music', 'volume', 'emails', 'schoolName'
    ])
    attrs.emails ?= {}
    attrs.emails.generalNews ?= {}
    # attrs.emails.generalNews.enabled = @$el.find('#subscribe').prop('checked')
    attrs.emails.generalNews.enabled = (attrs.subscribe[0] is 'on')
    delete attrs.subscribe
    
    # @classCode = attrs.classCode
    # delete attrs.classCode
  
    error = false
    # birthday = new Date Date.UTC attrs.birthdayYear, attrs.birthdayMonth - 1, attrs.birthdayDay
    # if @classCode
    #   attrs.role = 'student'
    # else if isNaN(birthday.getTime())
    #   forms.setErrorToProperty @$el, 'birthdayDay', 'Required'
    #   error = true
    # else
    #   age = (new Date().getTime() - birthday.getTime()) / 365.4 / 24 / 60 / 60 / 1000
    #   attrs.birthday = birthday.toISOString()
  
    # delete attrs.birthdayYear
    # delete attrs.birthdayMonth
    # delete attrs.birthdayDay
    if @sharedState.get('birthday')
      attrs.birthday = @sharedState.get('birthday').toISOString()

    _.assign attrs, @sharedState.get('ssoAttrs') if @sharedState.get('ssoAttrs')
    res = tv4.validateMultiple attrs, User.schema
  
    # forms.clearFormAlerts(@$el)
    # if not res.valid
    #   forms.applyErrorsToForm(@$el, res.errors)
    #   error = true
    # if not attrs.password
    #   forms.setErrorToProperty @$el, 'password', 'Required'
    #   error = true
    # if not forms.validateEmail(attrs.email)
    #   forms.setErrorToProperty @$el, 'email', 'Please enter a valid email address'
    #   error = true
    # return if error
  
    @$('#signup-button').text($.i18n.t('signup.creating')).attr('disabled', true)
    @newUser = new User(attrs)
    @createUser()

  createUser: ->
    options = {}
    window.tracker?.identify()
    if @sharedState.get('ssoUsed') is 'gplus'
      @newUser.set('_id', me.id)
      options.url = "/db/user?gplusID=#{@sharedState.get('ssoAttrs').gplusID}&gplusAccessToken=#{application.gplusHandler.accessToken.access_token}"
      options.type = 'PUT'
    if @sharedState.get('ssoUsed') is 'facebook'
      @newUser.set('_id', me.id)
      options.url = "/db/user?facebookID=#{@sharedState.get('ssoAttrs').facebookID}&facebookAccessToken=#{application.facebookHandler.authResponse.accessToken}"
      options.type = 'PUT'
    @newUser.save(null, options)
    @newUser.once 'sync', @onUserCreated, @
    @newUser.once 'error', @onUserSaveError, @
  
  onUserSaveError: (user, jqxhr) ->
    # TODO: Do we need to enable/disable the submit button to prevent multiple users being created?
    # Seems to work okay without that, but mongo had 2 copies of the user... temporarily. Very strange.
    if _.isObject(jqxhr.responseJSON) and jqxhr.responseJSON.property
      forms.applyErrorsToForm(@$el, [jqxhr.responseJSON])
      @setNameError(@state.get('suggestedName'))
    else
      console.log "Error:", jqxhr.responseText
      errors.showNotyNetworkError(jqxhr)
  
  onUserCreated: ->
    Backbone.Mediator.publish "auth:signed-up", {}
    if @sharedState.get('gplusAttrs')
      window.tracker?.trackEvent 'Google Login', category: "Signup", label: 'GPlus'
      window.tracker?.trackEvent 'Finished Signup', category: "Signup", label: 'GPlus'
    else if @sharedState.get('facebookAttrs')
      window.tracker?.trackEvent 'Facebook Login', category: "Signup", label: 'Facebook'
      window.tracker?.trackEvent 'Finished Signup', category: "Signup", label: 'Facebook'
    else
      window.tracker?.trackEvent 'Finished Signup', category: "Signup", label: 'CodeCombat'
    if @sharedState.get('classCode')
      url = "/courses?_cc="+@sharedState.get('classCode')
      location.href = url
    else
      window.location.reload()

  onClickSsoSignupButton: (e) ->
    e.preventDefault()
    ssoUsed = $(e.currentTarget).data('sso-used')
    if ssoUsed is 'facebook'
      handler = application.facebookHandler
      fetchSsoUser = 'fetchFacebookUser'
      idName = 'facebookID'
    else
      handler = application.gplusHandler
      fetchSsoUser = 'fetchGPlusUser'
      idName = 'gplusID'
    handler.connect({
      context: @
      success: ->
        handler.loadPerson({
          context: @
          success: (ssoAttrs) ->
            @sharedState.set { ssoAttrs }
            existingUser = new User()
            existingUser[fetchSsoUser](@sharedState.get('ssoAttrs')[idName], {
              context: @
              success: =>
                @sharedState.set {
                  ssoUsed
                  email: ssoAttrs.email
                }
                @trigger 'sso-connect:already-in-use'
              error: (user, jqxhr) =>
                @sharedState.set {
                  ssoUsed
                  email: ssoAttrs.email
                }
                @trigger 'sso-connect:new-user'
            })
        })
    })