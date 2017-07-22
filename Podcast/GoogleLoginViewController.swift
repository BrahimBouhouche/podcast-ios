
import UIKit
import SwiftyJSON
import GoogleSignIn
import GGLSignIn
import NVActivityIndicatorView

class GoogleLoginViewController: UIViewController, GIDSignInUIDelegate, GIDSignInDelegate {
    
    var loginButton: GIDSignInButton!
    var loadingActivityIndicator: NVActivityIndicatorView!
    var loginBackgroundGradientView: LoginBackgroundGradientView!
    var podcastLogoView: LoginPodcastLogoView!
    
    
    //Constants
    var loginButtonViewY: CGFloat = 362
    var podcastLogoViewY: CGFloat = 140
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError!)")
        
        GIDSignIn.sharedInstance().delegate = self
        GIDSignIn.sharedInstance().uiDelegate = self
        
        let profileScope = "https://www.googleapis.com/auth/userinfo.profile"
        let emailScope = "https://www.googleapis.com/auth/userinfo.email"

        GIDSignIn.sharedInstance().scopes.append(contentsOf: [profileScope, emailScope])
        
        loginBackgroundGradientView = LoginBackgroundGradientView(frame: view.frame)
        view.addSubview(loginBackgroundGradientView)
        
        loginButton = GIDSignInButton()
        loginButton.style = .wide
        loginButton.frame.origin.y = loginButtonViewY
        loginButton.center.x = view.center.x
        loginButton.addTarget(self, action: #selector(loginButtonPressed), for: .touchUpInside)
        view.addSubview(loginButton)
        
        podcastLogoView = LoginPodcastLogoView(frame: CGRect(x: 0, y: podcastLogoViewY, width: view.frame.width, height: view.frame.height / 4))
        podcastLogoView.center.x = view.center.x
        view.addSubview(podcastLogoView)
        
        loadingActivityIndicator = createLoadingAnimationView()
        loadingActivityIndicator.center = view.center
        loadingActivityIndicator.color = .podcastWhite
        view.addSubview(loadingActivityIndicator)
    }
    
    func loginButtonPressed() {
        loginButton.isHidden = true
        loadingActivityIndicator.startAnimating()
    }
    
    func signInSilently() {
        GIDSignIn.sharedInstance().signInSilently()
    }
    
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!) {
        
        guard error == nil else {
            print("\(error.localizedDescription)")
            loadingActivityIndicator.stopAnimating()
            self.loginButton.isHidden = false
            return
        }
        
        guard let idToken = user.authentication.idToken else { return } // Safe to send to the server

        let authenticateGoogleUserEndpointRequest = AuthenticateGoogleUserEndpointRequest(idToken: idToken)
        
        authenticateGoogleUserEndpointRequest.success = { (endpointRequest: EndpointRequest) in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            
            guard let result = endpointRequest.processedResponseValue as? [String: Any],
            let user = result["user"] as? User, let session = result["session"] as? Session, let isNewUser = result["newUser"] as? Bool else {
                print("error authenticating")
                return
            }
            
            System.currentUser = user
            System.currentSession = session
            
            self.loadingActivityIndicator.stopAnimating()
            self.loginButton.isHidden = false
            
            if isNewUser {
                let loginUsernameVC = LoginUsernameViewController()
                loginUsernameVC.user = user
                self.navigationController?.pushViewController(loginUsernameVC, animated: false)
            } else {
                appDelegate.didFinishAuthenticatingUser()
            }
        }
        
        authenticateGoogleUserEndpointRequest.failure = { (endpointRequest: EndpointRequest) in
            self.loadingActivityIndicator.stopAnimating()
            self.loginButton.isHidden = false
        }
        
        System.endpointRequestQueue.addOperation(authenticateGoogleUserEndpointRequest)
    }
    
    func logout() {
        GIDSignIn.sharedInstance().signOut()
    }
    
    func handleSignIn(url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        return GIDSignIn.sharedInstance().handle(url,
                                                 sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as? String,
                                                 annotation: options[UIApplicationOpenURLOptionsKey.annotation])
    }
}








