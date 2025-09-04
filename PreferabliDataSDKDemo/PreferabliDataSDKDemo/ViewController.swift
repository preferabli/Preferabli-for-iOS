//
//  ContentView.swift
//  WineRingSDKTest
//
//  Created by Nicholas Bortolussi on 5/29/20.
//  Copyright © 2020 RingIT, Inc,. All rights reserved.
//

import SwiftUI
import PreferabliDataSDK
import TTGSnackbar
import _SwiftData_SwiftUI

class ViewController : UIViewController, UIPickerViewDelegate, UIPickerViewDataSource, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak public var loginButton: UIButton!
    @IBOutlet weak public var customerButton: UIButton!
    @IBOutlet weak public var authenticatedButton: UIButton!
    @IBOutlet weak public var email: UITextField!
    @IBOutlet weak public var password: UITextField!
    @IBOutlet weak public var firstLabel: UILabel!
    @IBOutlet weak public var loadingView: UIView!
    @IBOutlet weak public var tableView: UITableView!
    @IBOutlet weak public var logo: UIImageView!
    
    var customer = true
    var picker : UIPickerView!
    var picker2 : UIPickerView!
    var toolBar : UIToolbar!
    let pickerOptions = ["Search", "Label Rec", "Guided Rec", "Where To Buy", "Like That, Try This"]
    let pickerOptions2 = ["Rate Product", "Wishlist Product", "Get Profile", "Get Recs", "Get Foods", "Get Rated Products", "Get Wishlisted Products", "Get Purchased Products", "Get Customer"]
    var items = Array<String>()
    @Query var products: [Product]

    override func viewDidLoad() {
        logo.image = Preferabli.getPoweredByPreferabliLogo(light_background: true)
        handleViews()
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return pickerView == picker ? pickerOptions.count : pickerOptions2.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return pickerView == picker ? pickerOptions[row] : pickerOptions2[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        return NSAttributedString(string: (pickerView == picker ? pickerOptions[row] : pickerOptions2[row]), attributes: [NSAttributedString.Key.foregroundColor: UIColor.white])
    }
    
    func handleViews() {
        if (Preferabli.isPreferabliUserLoggedIn() || Preferabli.isCustomerLoggedIn()) {
            email.isHidden = true
            password.isHidden = true
            loginButton.setTitle("LOGOUT", for: .normal)
            firstLabel.text = "You are now browsing as an authenticated " + (Preferabli.isPreferabliUserLoggedIn() ? "Preferabli user" : "customer") +  ". You can log them out below."
            customerButton.isHidden = true
            authenticatedButton.isHidden = false
        } else {
            email.isHidden = false
            password.isHidden = customer
            email.placeholder = customer ? "Customer ID (Email or Phone)" : "Preferabli User Email"
            loginButton.setTitle("SUBMIT", for: .normal)
            firstLabel.text = "To unlock additional actions, link a customer..."
            customerButton.setTitle(customer ? "Link a Customer" : "Preferabli User Login", for: .normal)
            customerButton.isHidden = true
            authenticatedButton.isHidden = true
        }
    }
    
    @objc func dismissPicker() {
        if (toolBar != nil) {
            toolBar.removeFromSuperview()
        }
        if (picker != nil) {
            picker.removeFromSuperview()
        }
        if (picker2 != nil) {
            picker2.removeFromSuperview()
        }
    }
    
    @objc func runUnauthenticatedAction() {
        let result = pickerOptions[picker.selectedRow(inComponent: 0)]
        doAction(result: result)
    }
    
    @objc func runAuthenticatedAction() {
        let result = pickerOptions2[picker2.selectedRow(inComponent: 0)]
        doAction(result: result)
    }
    
    func doAction(result : String) {
        if (result == "Search") {
            searchProductsPressed()
        } else if (result == "Label Rec") {
            labelRecPressed()
        } else if (result == "Guided Rec") {
            guidedRecPressed()
        } else if (result == "Where To Buy") {
            whereToBuyPressed()
        } else if (result == "Like That, Try This") {
            ltttPressed()
        } else if (result == "Get Profile") {
            getProfilePressed()
        } else if (result == "Get Foods") {
            getFoodsPressed()
        } else if (result == "Get Recs") {
            getRecPressed()
        } else if (result == "Get Rated Products") {
            getRatedProductsPressed()
        } else if (result == "Get Wishlisted Products") {
            getWishlistedProductsPressed()
        } else if (result == "Get Purchased Products") {
            getPurchasedProductsPressed()
        } else if (result == "Rate Product") {
            rateProductPressed()
        } else if (result == "Wishlist Product") {
            wishlistProductPressed()
        } else if (result == "Get Customer") {
            getCustomer()
        }
        dismissPicker()
    }
    
    @IBAction func unauthenticatedPressed() {
        dismissPicker()
        picker = UIPickerView(frame: CGRect.init(x: 0.0, y: UIScreen.main.bounds.size.height - 300, width: UIScreen.main.bounds.size.width, height: 300))
        picker?.backgroundColor = .black
        picker?.tintColor = .white
        picker?.delegate = self
        picker?.dataSource = self
        view.addSubview(picker!)
        
        toolBar = UIToolbar.init(frame: CGRect.init(x: 0.0, y: UIScreen.main.bounds.size.height - 300, width: UIScreen.main.bounds.size.width, height: 50))
        toolBar?.barStyle = UIBarStyle.default
        toolBar?.isTranslucent = false
        toolBar?.barTintColor = .black
        toolBar?.tintColor = .white
        toolBar?.sizeToFit()
        
        let spaceButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "RUN ACTION", style: UIBarButtonItem.Style.done, target: self, action: #selector(runUnauthenticatedAction))
        let cancelButton = UIBarButtonItem(title: "CANCEL", style: UIBarButtonItem.Style.plain, target: self, action: #selector(dismissPicker))
        
        toolBar?.setItems([cancelButton, spaceButton, doneButton], animated: false)
        toolBar?.isUserInteractionEnabled = true
        view.addSubview(toolBar!)
    }
    
    @IBAction func authenticatedPressed() {
        dismissPicker()
        picker2 = UIPickerView(frame: CGRect.init(x: 0.0, y: UIScreen.main.bounds.size.height - 300, width: UIScreen.main.bounds.size.width, height: 300))
        picker2?.backgroundColor = .black
        picker2?.tintColor = .white
        picker2?.delegate = self
        picker2?.dataSource = self
        view.addSubview(picker2!)
        
        toolBar = UIToolbar.init(frame: CGRect.init(x: 0.0, y: UIScreen.main.bounds.size.height - 300, width: UIScreen.main.bounds.size.width, height: 50))
        toolBar?.barStyle = UIBarStyle.default
        toolBar?.isTranslucent = false
        toolBar?.barTintColor = .black
        toolBar?.tintColor = .white
        toolBar?.sizeToFit()
        
        let spaceButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "RUN ACTION", style: UIBarButtonItem.Style.done, target: self, action: #selector(runAuthenticatedAction))
        let cancelButton = UIBarButtonItem(title: "CANCEL", style: UIBarButtonItem.Style.plain, target: self, action: #selector(dismissPicker))
        
        toolBar?.setItems([cancelButton, spaceButton, doneButton], animated: false)
        toolBar?.isUserInteractionEnabled = true
        view.addSubview(toolBar)
    }
    
    @IBAction func customerPressed() {
        customer = !customer
        handleViews()
    }
    
    // Login before you can perform any actions associated with a user.
    @IBAction func loginPressed() {
        showLoadingView()
        hideKeyboard()
        
        if (Preferabli.isPreferabliUserLoggedIn() || Preferabli.isCustomerLoggedIn()) {
            Preferabli.main.logout() {
                self.products.removeAll()
                self.items = ["Logged out."]
                self.tableView.reloadData()
                self.hideLoadingView()
                self.handleViews()
            } onFailure: { error in
                self.hideLoadingView()
                self.showSnackBar(message: error.getMessage())
            }
        } else if (customer) {
            let emailString = email.text ?? ""
            
            Preferabli.main.loginCustomer(merchant_customer_identification: emailString, merchant_customer_verification: "ABC123") { customer in
                self.products.removeAll()
                self.items = ["Customer logged in.", "Display Name: " + customer.getName()]
                self.tableView.reloadData()
                self.hideLoadingView()
                self.handleViews()
            } onFailure: { error in
                self.hideLoadingView()
                self.showSnackBar(message: error.getMessage())
            }
        } else {
            let emailString = email.text ?? ""
            let passwordString = password.text ?? ""
            
            Preferabli.main.loginPreferabliUser(email: emailString, password: passwordString) { user in
                self.products.removeAll()
                self.items = ["Preferabli User logged in.", "Display Name: " + (user.display_name ?? "")]
                self.tableView.reloadData()
                self.hideLoadingView()
                self.handleViews()
            } onFailure: { error in
                self.hideLoadingView()
                self.showSnackBar(message: error.getMessage())
            }
        }
    }
    
    func getCustomer() {
        Preferabli.main.getCustomer { customer in
            self.products.removeAll()
            self.items = ["Got the customer.", "Display Name: " + customer.getName()]
            self.tableView.reloadData()
            self.hideLoadingView()
            self.handleViews()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func searchProductsPressed() {
        showLoadingView()
        Preferabli.main.searchProducts(query: "wine") { products in
            self.products = products
            self.items = products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func labelRecPressed() {
        showLoadingView()
        Preferabli.main.labelRecognition(image: UIImage.init(named: "label_rec_example.png")!) { (media, products) in
            self.products = products.map { $0.product }
            self.items = products.map { $0.product.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func guidedRecPressed() {
        showLoadingView()
        
        Preferabli.main.getGuidedRec { guided_rec in
            let questions = guided_rec.questions
            var selected_choice_ids = Array<Int>()
            for question in questions {
                if (question.choices.count > 0) {
                    selected_choice_ids.append(question.choices.randomElement()!.id)
                }
            }
            
            Preferabli.main.getGuidedRecResults(guided_rec_id: guided_rec.id, selected_choice_ids: selected_choice_ids) { products in
                self.products = products
                self.items = products.map { $0.name } as! [String]
                self.tableView.reloadData()
                self.hideLoadingView()
            } onFailure: { error in
                self.hideLoadingView()
                self.showSnackBar(message: error.getMessage())
            }
            
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
        
        Preferabli.main.getGuidedRec { guided_rec in
            let questions = guided_rec.questions
            var selected_choice_ids = Array<Int>()
                for question in questions {
                    if (question.choices.count > 0) {
                         // Here I am simply randomizing choices to get results. In the real world, the answers to these questions would come from the user.
                        selected_choice_ids.append(question.choices.randomElement()!.id)
                    }
                }
                    
            Preferabli.main.getGuidedRecResults(guided_rec_id: guided_rec.id, selected_choice_ids: selected_choice_ids) { products in
                // Do what you like with the message & products returned.
            } onFailure: { error in
                // Call failed.
            }
        } onFailure: { error in
            // Call failed.
            }
    }
    
    @IBAction func whereToBuyPressed() {
        showLoadingView()
        Preferabli.main.getPreferabliProductId(merchant_variant_id: "107811") { product_id in
            Preferabli.main.whereToBuy(product_id: product_id) { where_to_buy in
                self.products.removeAll()
                if where_to_buy.links.count > 0 {
                    self.items = where_to_buy.links.map { $0.product_name } as! [String]
                } else {
                    self.items = where_to_buy.venues.map { $0.name } as! [String]
                }
                self.tableView.reloadData()
                self.hideLoadingView()
            } onFailure: { error in
                self.hideLoadingView()
                self.showSnackBar(message: error.getMessage())
            }
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func ltttPressed() {
        showLoadingView()
        Preferabli.main.lttt(product_id: 11263) { ids in
            self._products = Query(
                filter: Storage.Queries.products(withIDs: ids),
                sort: Storage.Queries.sortByUpdatedDesc
            )
            self.items = self.products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func rateProductPressed() {
        showLoadingView()
        Preferabli.main.rateProduct(product_id: 11263, year: Variant.CURRENT_VARIANT_YEAR, rating: RatingLevel.SOSO) { product in
            self.products = [product]
            self.items = [ product.name ?? "N/A" ]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func wishlistProductPressed() {
        showLoadingView()
        Preferabli.main.wishlistProduct(product_id: 11263, year: Variant.CURRENT_VARIANT_YEAR) { product in
            self.products = [product]
            self.items = [ product.name ?? "N/A" ]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getProfilePressed() {
        showLoadingView()
        Preferabli.main.getProfile { profile in
            self.products.removeAll()
            self.items = profile.profile_styles.map { $0.style?.name ?? "N/A" } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getFoodsPressed() {
        showLoadingView()
        Preferabli.main.getFoods { foods in
            self.products.removeAll()
            self.items = foods.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getRecPressed() {
        showLoadingView()
        Preferabli.main.getRecs(product_category: ProductCategory.WINE, product_type: ProductType.RED) { (message, products) in
            self.products = products
            self.items = products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getRatedProductsPressed() {
        showLoadingView()
        Preferabli.main.getRatedProducts { products in
            self.products = products
            self.items = products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getWishlistedProductsPressed() {
        showLoadingView()
        Preferabli.main.getWishlistedProducts { products in
            self.products = products
            self.items = products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    @IBAction func getPurchasedProductsPressed() {
        showLoadingView()
        Preferabli.main.getPurchasedProducts { products in
            self.products = products
            self.items = products.map { $0.name } as! [String]
            self.tableView.reloadData()
            self.hideLoadingView()
        } onFailure: { error in
            self.hideLoadingView()
            self.showSnackBar(message: error.getMessage())
        }
    }
    
    func showLoadingView() {
        loadingView.isHidden = false
    }
    
    func hideLoadingView() {
        loadingView.isHidden = true
    }
    
    public func hideKeyboard() {
        self.view.endEditing(true)
    }
    
    public func showSnackBar(message: String) {
        let snackbar = TTGSnackbar.init(message: message, duration: .long)
        snackbar.show()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") as! CustomTableViewCell
        cell.label.text = items[indexPath.row]
        return cell
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hideKeyboard()
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        hideKeyboard()
        if (products.count > 0 && products.count > indexPath.row) {
            let wtb = UIAction(title: "Where To Buy") { _ in
                self.showLoadingView()
                self.products[indexPath.row].whereToBuy() { where_to_buy in
                    self.products.removeAll()
                    if where_to_buy.links.count > 0 {
                        self.items = where_to_buy.links.map { $0.product_name } as! [String]
                    } else {
                        self.items = where_to_buy.venues.map { $0.name } as! [String]
                    }
                    self.tableView.reloadData()
                    self.hideLoadingView()
                } onFailure: { error in
                    self.hideLoadingView()
                    self.showSnackBar(message: error.getMessage())
                }
            }
            let wishlist = UIAction(title: "Toggle Wishlist") { _ in
                self.showLoadingView()
                self.products[indexPath.row].toggleWishlist() { product in
                    self.products = [product]
                    self.items = [ product.name ?? "N/A" ]
                    self.tableView.reloadData()
                    self.hideLoadingView()
                } onFailure: { error in
                    self.hideLoadingView()
                    self.showSnackBar(message: error.getMessage())
                }
            }
            let rate = UIAction(title: "Rate") { _ in
                self.showLoadingView()
                self.products[indexPath.row].rate(rating: .LOVE) { product in
                    self.products = [product]
                    self.items = [ product.name ?? "N/A" ]
                    self.tableView.reloadData()
                    self.hideLoadingView()
                } onFailure: { error in
                    self.hideLoadingView()
                    self.showSnackBar(message: error.getMessage())
                }
            }
            let lttt = UIAction(title: "LTTT") { _ in
                self.showLoadingView()
                self.products[indexPath.row].lttt() { products in
                    self.products = products
                    self.items = products.map { $0.name } as! [String]
                    self.tableView.reloadData()
                    self.hideLoadingView()
                } onFailure: { error in
                    self.hideLoadingView()
                    self.showSnackBar(message: error.getMessage())
                }
            }
            let score = UIAction(title: "Get Preferabli Score") { _ in
                self.showLoadingView()
                self.products[indexPath.row].getPreferabliScore() { score in
                    self.products.removeAll()
                    let item = score.getMessage()
                    self.items = [ item ]
                    self.tableView.reloadData()
                    self.hideLoadingView()
                } onFailure: { error in
                    self.hideLoadingView()
                    self.showSnackBar(message: error.getMessage())
                }
            }
            
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
                let menu : UIMenu
                if (Preferabli.isCustomerLoggedIn() || Preferabli.isPreferabliUserLoggedIn()) {
                    menu = UIMenu(title: self.items[indexPath.row], children: [wtb, lttt, rate, wishlist, score])
                } else {
                    menu = UIMenu(title: self.items[indexPath.row], children: [wtb, lttt])
                }
                return menu
            })
        }
        return nil
    }
}
